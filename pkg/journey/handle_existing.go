package journey

import "fmt"

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
	ctx.IntegrationTestScenarioName = fmt.Sprintf("%s-its", appName)

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

	logging.Logger.Info("Adopted existing component %s in namespace %s", ctx.ComponentName, ctx.ParentContext.ParentContext.Namespace)
	return nil
}

// TriggerComponentBuild pushes a trivial change to the component repo (via doHarmlessCommit) to
// trigger a fresh PaC build PipelineRun on the adopted Component.
func TriggerComponentBuild(ctx *types.PerComponentContext, repoUrl, repoRevision string) error {
	if repoUrl == "" {
		return logging.Logger.Fail(202, "Component repo URL not provided")
	}

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
