package journey

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

// HandleExistingApplication adopts an already-onboarded Application (and its matching
// IntegrationTestScenario) for the probe, validating that it exists in the target namespace.
// It never creates or deletes the Application — that setup happens out-of-band.
func HandleExistingApplication(ctx *types.PerApplicationContext, appName string) error {
	if appName == "" {
		return logging.Logger.Fail(200, "Application name not provided")
	}

	ctx.ApplicationName = appName

	// Fail fast: the ITS name is only needed when the integration test stage is actually
	// awaited. It can be skipped by disabling pipeline waits or by leaving the test-scenario GIT
	// URL empty (wait for the Snapshot only). We never derive a default name.
	itsSkipped := !ctx.ParentContext.Opts.WaitPipelines || !ctx.ParentContext.Opts.WaitIntegrationTestsPipelines || ctx.ParentContext.Opts.TestScenarioGitURL == ""
	if !itsSkipped {
		if ctx.ParentContext.Opts.IntegrationTestScenarioName == "" {
			return logging.Logger.Fail(200, "integration test scenario name not provided: set --integration-test-scenario, or skip the integration test stage (--test-scenario-git-url \"\")")
		}
		ctx.IntegrationTestScenarioName = ctx.ParentContext.Opts.IntegrationTestScenarioName
	}

	_, err := logging.Measure(
		ctx,
		validateApplication,
		ctx.Framework,
		ctx.ApplicationName,
		ctx.ParentContext.Namespace,
	)
	if err != nil {
		return logging.Logger.Fail(200, "Application failed validation: %v", err)
	}

	logging.Logger.Info("Adopted existing application %s in namespace %s", ctx.ApplicationName, ctx.ParentContext.Namespace)
	return nil
}

// HandleExistingComponent adopts an already-onboarded Component for the probe, validating that it
// exists in the target namespace. It never creates or deletes the Component.
func HandleExistingComponent(ctx *types.PerComponentContext, compName string) error {
	if compName == "" {
		return logging.Logger.Fail(201, "Component name not provided")
	}

	ctx.ComponentName = compName

	_, err := logging.Measure(
		ctx,
		validateComponent,
		ctx.Framework,
		ctx.ParentContext.ParentContext.Namespace,
		ctx.ComponentName,
	)
	if err != nil {
		return logging.Logger.Fail(201, "Component failed validation: %v", err)
	}

	// Derive the build-trigger repo from the adopted Component CR so the probe never has to be
	// told the repo (--component-repo was removed). The PaC pipeline config lives on this repo, so
	// the harmless commit must land on it to trigger a fresh build.
	comp, err := ctx.Framework.AsKubeDeveloper.HasController.GetComponent(ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace)
	if err != nil {
		return logging.Logger.Fail(201, "Unable to get component %s in namespace %s: %v", ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace, err)
	}
	if comp.Spec.Source.GitSource == nil || comp.Spec.Source.GitSource.URL == "" {
		return logging.Logger.Fail(201, "component %s in namespace %s does not have a git source URL", ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace)
	}
	if comp.Spec.Source.GitSource.Revision == "" {
		return logging.Logger.Fail(201, "component %s in namespace %s does not have a git source revision (branch)", ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace)
	}
	ctx.ParentContext.ParentContext.ComponentRepoUrl = comp.Spec.Source.GitSource.URL
	ctx.ParentContext.ParentContext.ComponentRepoRevision = comp.Spec.Source.GitSource.Revision
	logging.Logger.Debug("Derived component %s source repo %s (revision %s)", ctx.ComponentName, ctx.ParentContext.ParentContext.ComponentRepoUrl, ctx.ParentContext.ParentContext.ComponentRepoRevision)

	logging.Logger.Info("Adopted existing component %s in namespace %s", ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace)
	return nil
}

// TriggerComponentBuild pushes a trivial change to the component repo (via doHarmlessCommit) to
// trigger a fresh PaC build PipelineRun on the adopted Component. The repo and revision come from
// the Component CR (set by HandleExistingComponent), not from command-line options.
func TriggerComponentBuild(ctx *types.PerComponentContext) error {
	repoUrl := ctx.ParentContext.ParentContext.ComponentRepoUrl
	repoRevision := ctx.ParentContext.ParentContext.ComponentRepoRevision

	_, err := logging.Measure(
		ctx,
		doHarmlessCommit,
		ctx.Framework,
		repoUrl,
		repoRevision,
	)
	if err != nil {
		return logging.Logger.Fail(202, "Failed to trigger build via harmless commit: %v", err)
	}

	logging.Logger.Info("Triggered build for component %s via harmless commit", ctx.ComponentName)
	return nil
}
