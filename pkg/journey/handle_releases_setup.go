package journey

import "fmt"
import "time"

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

import framework "github.com/konflux-ci/e2e-tests/pkg/framework"
import utils "github.com/konflux-ci/e2e-tests/pkg/utils"

// Create ReleasePlan CR
func createReleasePlan(f *framework.Framework, namespace, appName string) (string, error) {
	name := appName + "-rp"
	logging.Logger.Debug("Creating release plan %s in namespace %s", name, namespace)

	_, err := f.AsKubeDeveloper.ReleaseController.CreateReleasePlan(name, namespace, appName, namespace, "true", nil, nil, nil)
	if err != nil {
		return "", fmt.Errorf("unable to create the releasePlan %s in %s: %v", name, namespace, err)
	}

	return name, nil
}


// Create ReleasePlanAdmission CR
// Assumes enterprise contract policy and service account with required permissions is already there
func createReleasePlanAdmission(f *framework.Framework, namespace, appName, policyName, releasePipelineSAName, releasePipelineUrl, releasePipelineRevision, releasePipelinePath string, releaseOciStorage string) (string, error) {
	name := appName + "-rpa"
	logging.Logger.Debug("Creating release plan admission %s in namespace %s with policy %s and pipeline SA %s", name, namespace, policyName, releasePipelineSAName)

	_, err := f.AsKubeDeveloper.ReleaseController.CreateReleasePlanAdmissionWithGitPipeline(name, namespace, namespace, policyName, releasePipelineSAName, []string{appName}, true, releasePipelineUrl, releasePipelineRevision, releasePipelinePath, releaseOciStorage, nil)
	if err != nil {
		return "", fmt.Errorf("unable to create the releasePlanAdmission %s in %s: %v", name, namespace, err)
	}

	return name, nil
}


// Wait for ReleasePlan CR to be created and to have status "Matched"
func validateReleasePlan(f *framework.Framework, namespace, name string) error {
	logging.Logger.Debug("Validating release plan %s in namespace %s", name, namespace)

	interval := time.Second * 10
	timeout := time.Minute * 5

	err := utils.WaitUntilWithInterval(func() (done bool, err error) {
		releasePlan, err := f.AsKubeDeveloper.ReleaseController.GetReleasePlan(name, namespace)
		if err != nil {
			logging.Logger.Debug("Unable to get ReleasePlan %s in %s: %v\n", name, namespace, err)
			return false, nil
		}

		condition := f.AsKubeDeveloper.ReleaseController.GetReleasePlanMatchedCondition(releasePlan)
		if condition == nil {
			logging.Logger.Debug("MatchedConditon of %s is still not set\n", releasePlan.Name)
			return false, nil
		}

		if f.AsKubeDeveloper.ReleaseController.IsReleasePlanMatched(releasePlan) {
			return true, nil
		}

		logging.Logger.Debug("MatchedConditon of %s not matched yet: %v\n", releasePlan.Name, condition)
		return false, nil
	}, interval, timeout)

	return err
}


// Wait for ReleasePlanAdmission CR to be created and to have status "Matched"
func validateReleasePlanAdmission(f *framework.Framework, namespace, name string) error {
	logging.Logger.Debug("Validating release plan admission %s in namespace %s", name, namespace)

	interval := time.Second * 10
	timeout := time.Minute * 5

	err := utils.WaitUntilWithInterval(func() (done bool, err error) {
		releasePlanAdmission, err := f.AsKubeDeveloper.ReleaseController.GetReleasePlanAdmission(name, namespace)
		if err != nil {
			logging.Logger.Debug("Unable to get ReleasePlanAdmission %s in %s: %v\n", name, namespace, err)
			return false, nil
		}

		condition := f.AsKubeDeveloper.ReleaseController.GetReleasePlanAdmissionMatchedCondition(releasePlanAdmission)
		if condition == nil {
			logging.Logger.Debug("MatchedConditon of %s is still not set\n", releasePlanAdmission.Name)
			return false, nil
		}

		if f.AsKubeDeveloper.ReleaseController.IsReleasePlanAdmissionMatched(releasePlanAdmission) {
			return true, nil
		}

		logging.Logger.Debug("MatchedConditon of %s not matched yet: %v\n", releasePlanAdmission.Name, condition)
		return false, nil
	}, interval, timeout)

	return err
}


func HandleReleaseSetup(ctx *types.PerApplicationContext) error {
	if ctx.ReleasePlanName != "" {
		if ctx.ReleasePlanAdmissionName == "" {
			return logging.Logger.Fail(90, "We are supposed to reuse RPA, but it was not configured")
		}
		logging.Logger.Debug("Skipping setting up releases because reusing release plan %s and release plan admission %s in namespace %s", ctx.ReleasePlanName, ctx.ReleasePlanAdmissionName, ctx.ParentContext.Namespace)
		return nil
	}

	if ctx.ParentContext.Opts.ReleasePolicy == "" {
		logging.Logger.Info("Skipping setting up releases because policy was not provided")
		return nil
	}

	var iface interface{}
	var ok bool
	var err error

	iface, err = logging.Measure(
		ctx,
		createReleasePlan,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ApplicationName,
	)
	if err != nil {
		return logging.Logger.Fail(91, "Release Plan failed creation: %v", err)
	}

	ctx.ReleasePlanName, ok = iface.(string)
	if !ok {
		return logging.Logger.Fail(92, "Type assertion failed on release plan name: %+v", iface)
	}

	iface, err = logging.Measure(
		ctx,
		createReleasePlanAdmission,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ApplicationName,
		ctx.ParentContext.Opts.ReleasePolicy,
		ctx.ParentContext.Opts.ReleasePipelineServiceAccount,
		ctx.ParentContext.Opts.ReleasePipelineUrl,
		ctx.ParentContext.Opts.ReleasePipelineRevision,
		ctx.ParentContext.Opts.ReleasePipelinePath,
		ctx.ParentContext.Opts.ReleaseOciStorage,
	)
	if err != nil {
		return logging.Logger.Fail(93, "Release Plan Admission failed creation: %v", err)
	}

	ctx.ReleasePlanAdmissionName, ok = iface.(string)
	if !ok {
		return logging.Logger.Fail(94, "Type assertion failed on release plan admission name: %+v", iface)
	}

	_, err = logging.Measure(
		ctx,
		validateReleasePlan,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ReleasePlanName,
	)
	if err != nil {
		return logging.Logger.Fail(95, "Release Plan failed validation: %v", err)
	}

	_, err = logging.Measure(
		ctx,
		validateReleasePlanAdmission,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ReleasePlanAdmissionName,
	)
	if err != nil {
		return logging.Logger.Fail(96, "Release Plan Admission failed validation: %v", err)
	}


	logging.Logger.Info("Configured release %s & %s for application %s in namespace %s", ctx.ReleasePlanName, ctx.ReleasePlanAdmissionName, ctx.ApplicationName, ctx.ParentContext.Namespace)

	return nil
}
