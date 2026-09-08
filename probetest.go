//go:build ignore

package main

import "fmt"
import "strings"

import journey "github.com/konflux-ci/loadtest/pkg/journey"
import options "github.com/konflux-ci/loadtest/pkg/options"
import logging "github.com/konflux-ci/loadtest/pkg/logging"
import loadtestutils "github.com/konflux-ci/loadtest/pkg/loadtestutils"
import types "github.com/konflux-ci/loadtest/pkg/types"

import cobra "github.com/spf13/cobra"
import klog "k8s.io/klog/v2"
import textlogger "k8s.io/klog/v2/textlogger"
import ctrl "sigs.k8s.io/controller-runtime"

// This is a simplified Konflux health-check probe (KONFLUX-15732). It adopts a fixed,
// pre-onboarded Application/Component (never creating or deleting them), triggers a fresh PaC build
// via a harmless commit, and waits on the build / integration test / release PipelineRuns. It reuses
// the existing journey, types, options and logging packages from the full loadtest, but strips the
// rare/one-off steps (repo forking, component onboarding, pinned task-bundle references).

var opts = options.Opts{}

var rootCmd = &cobra.Command{
	Use:   "probetest",
	Short: "Konflux core-component health probe",
	Long:  `Konflux core-component health probe (simplified loadtest that adopts a fixed Application/Component)`,
}

func init() {
	rootCmd.Flags().StringVar(&opts.ApplicationName, "application", "", "the existing Application CR name to adopt")
	rootCmd.Flags().StringVar(&opts.ComponentName, "component", "", "the existing Component CR name to adopt (the build-trigger repo and revision are derived from the Component CR)")
	rootCmd.Flags().StringVar(&opts.IntegrationTestScenarioName, "integration-test-scenario", "", "the existing IntegrationTestScenario CR name to adopt (required unless the integration test stage is skipped via --test-scenario-git-url \"\" or --waitintegrationtestspipelines false)")
	rootCmd.Flags().StringVar(&opts.TestScenarioGitURL, "test-scenario-git-url", "https://github.com/konflux-ci/integration-examples.git", "test scenario GIT URL; only emptiness matters here: non-empty waits for the integration test PipelineRun, empty (\"\") waits only for the Snapshot and skips the integration test PipelineRun")
	rootCmd.Flags().StringVar(&opts.ReleasePolicy, "release-policy", "", "enterprise contract policy name; only emptiness matters here: non-empty waits for the release, empty (\"\") skips the release stage")
	rootCmd.Flags().StringVar(&opts.ReleaseManagedNamespace, "release-managed-namespace", "", "managed namespace where the release pipeline runs (release PLR is monitored here instead of the tenant namespace)")
	rootCmd.Flags().StringVar(&opts.ReleaseManagedToken, "release-managed-token", "", "SA token for accessing the managed release namespace")
	rootCmd.Flags().BoolVarP(&opts.WaitPipelines, "waitpipelines", "w", true, "if you want to wait for build pipelines to finish")
	rootCmd.Flags().BoolVarP(&opts.WaitIntegrationTestsPipelines, "waitintegrationtestspipelines", "i", true, "if you want to wait for IntegrationTests pipelines to finish")
	rootCmd.Flags().BoolVarP(&opts.WaitRelease, "waitrelease", "r", true, "if you want to wait for Release to finish")
	rootCmd.Flags().StringVarP(&opts.OutputDir, "output-dir", "o", ".", "directory where output files such as load-tests.log or load-test-timings.csv are stored")
	rootCmd.Flags().BoolVarP(&opts.LogInfo, "log-info", "v", false, "log messages with info level and above")
	rootCmd.Flags().BoolVarP(&opts.LogDebug, "log-debug", "d", false, "log messages with debug level and above")
	rootCmd.Flags().BoolVarP(&opts.LogTrace, "log-trace", "t", false, "log messages with trace level and above (i.e. everything)")
	rootCmd.Flags().BoolVarP(&opts.Stage, "stage", "s", false, "use the first user's token/APIURL from users.json instead of the local kubeconfig")
}

func main() {
	var err error

	// Setup logging
	klog.InitFlags(nil)
	defer klog.Flush()
	// Set the controller-runtime logger to use klogr.
	ctrl.SetLogger(textlogger.NewLogger(textlogger.NewConfig()))

	// Setup argument parser
	err = rootCmd.Execute()
	if err != nil {
		klog.Fatalln(err)
	}
	if rootCmd.Flags().Lookup("help").Value.String() == "true" {
		fmt.Println(rootCmd.UsageString())
		return
	}
	err = opts.ProcessOptionsForProbe()
	if err != nil {
		logging.Logger.Fatal("Failed to process options: %v", err)
	}

	// Setup logging
	logging.Logger.Level = logging.WARNING
	if opts.LogInfo {
		logging.Logger.Level = logging.INFO
	}
	if opts.LogDebug {
		logging.Logger.Level = logging.DEBUG
	}
	if opts.LogTrace {
		logging.Logger.Level = logging.TRACE
	}

	// Show test options
	logging.Logger.Debug("Options: %+v", &opts)

	// Tier up measurements logger. Must run before any journey.Handle* call, since those use
	// logging.Measure, which sends on measurementsQueue.
	logging.MeasurementsStart(opts.OutputDir)
	defer logging.MeasurementsStop()

	// Provision the framework.
	//
	// With --stage, the first user from users.json provides the APIURL/token used to authenticate
	// against a remote Konflux cluster (same as loadtest.go); the username is derived from that
	// user's namespace. Without --stage, we fall back to the local kubeconfig and target the existing
	// fixed tenant namespace through the E2E_APPLICATIONS_NAMESPACE env var, in which case the
	// username argument is irrelevant.
	var stageUsers []loadtestutils.User
	username := "probe"
	if opts.Stage {
		stageUsers, err = loadtestutils.LoadStageUsers("users.json")
		if err != nil {
			logging.Logger.Fatal("Failed to load Stage users: %v", err)
		}
		username = strings.TrimSuffix(stageUsers[0].Namespace, "-tenant")
	}

	f, namespace, err := journey.ProvisionFramework(stageUsers, 0, username, opts.Stage)
	if err != nil {
		logging.Logger.Fatal("Unable to provision framework: %v", err)
	}

	userCtx := &types.PerUserContext{Opts: &opts, Framework: f, Namespace: namespace, UserIndex: 0, StageUsers: &stageUsers}
	appCtx := &types.PerApplicationContext{ParentContext: userCtx, Framework: f}
	compCtx := &types.PerComponentContext{ParentContext: appCtx, Framework: f}

	// Adopt the fixed Application/Component, then drive one build -> test -> release cycle.
	if _, err := logging.Measure(appCtx, journey.HandleExistingApplication, appCtx, opts.ApplicationName); err != nil {
		logging.Logger.Fatal("Adopting application failed: %v", err)
	}
	if _, err := logging.Measure(compCtx, journey.HandleExistingComponent, compCtx, opts.ComponentName); err != nil {
		logging.Logger.Fatal("Adopting component failed: %v", err)
	}
	if _, err := logging.Measure(compCtx, journey.TriggerComponentBuild, compCtx); err != nil {
		logging.Logger.Fatal("Triggering component build failed: %v", err)
	}
	if _, err := logging.Measure(compCtx, journey.HandlePipelineRun, compCtx); err != nil {
		logging.Logger.Fatal("Build pipeline run failed: %v", err)
	}
	if _, err := logging.Measure(compCtx, journey.HandleTest, compCtx); err != nil {
		logging.Logger.Fatal("Test pipeline run failed: %v", err)
	}
	// Provision a managed framework so HandleReleaseRun can watch the release PipelineRun in the
	// managed namespace (when --release-managed-namespace is set). No-op otherwise.
	if _, err := logging.Measure(compCtx, journey.HandleNewManagedFrameworkForComp, compCtx); err != nil {
		logging.Logger.Fatal("Setting up managed framework failed: %v", err)
	}
	if _, err := logging.Measure(compCtx, journey.HandleReleaseRun, compCtx); err != nil {
		logging.Logger.Fatal("Release run failed: %v", err)
	}

	// Collect resources (never purged — the app/component are permanent fixtures).
	if _, err := logging.Measure(compCtx, journey.HandlePerComponentCollection, compCtx); err != nil {
		logging.Logger.Error("Per component collection failed: %v", err)
	}
	if _, err := logging.Measure(appCtx, journey.HandlePerApplicationCollection, appCtx); err != nil {
		logging.Logger.Error("Per application collection failed: %v", err)
	}
	if _, err := logging.Measure(userCtx, journey.HandlePerUserCollection, userCtx); err != nil {
		logging.Logger.Error("Per user collection failed: %v", err)
	}

	logging.Logger.Info("Probe run completed successfully")
}
