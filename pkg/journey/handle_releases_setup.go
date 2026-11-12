package journey

import "context"
import "encoding/json"
import "fmt"
import "os"
import "strings"
import "time"
import "unicode"

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

import framework "github.com/konflux-ci/e2e-tests/pkg/framework"
import utils "github.com/konflux-ci/e2e-tests/pkg/utils"

import releaseApi "github.com/konflux-ci/release-service/api/v1alpha1"
import releaseMetadata "github.com/konflux-ci/release-service/metadata"

import k8serrors "k8s.io/apimachinery/pkg/api/errors"
import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
import "k8s.io/apimachinery/pkg/runtime"

// sanitizeLabelValue makes the provided author usable as a Kubernetes label value.
// It mirrors what the release-service author webhook does to the requesting username:
// colons are replaced with underscores, the first at sign with a dot, the value is
// truncated to the maximum label length and trailing non-alphanumeric characters are removed.
func sanitizeLabelValue(author string) string {
	sanitized := strings.ReplaceAll(author, ":", "_")
	sanitized = strings.Replace(sanitized, "@", ".", 1)
	if len(sanitized) > releaseMetadata.MaxLabelLength {
		sanitized = sanitized[0:releaseMetadata.MaxLabelLength]
	}
	return strings.TrimRightFunc(sanitized, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
}

// Create ReleasePlan CR
// The release-service author webhook rejects ReleasePlans authored by a service account, so the
// author label is set explicitly to the configured human identity (or team identity) when creating it.
func createReleasePlan(f *framework.Framework, namespace, appName, targetNamespace, author string) (string, error) {
	name := appName + "-rp"
	logging.Logger.Debug("Creating release plan %s in namespace %s targeting %s with author %s", name, namespace, targetNamespace, author)

	labels := map[string]string{
		releaseMetadata.AttributionLabel: "true",
		releaseMetadata.AutoReleaseLabel: "true",
	}
	if author != "" {
		labels[releaseMetadata.AuthorLabel] = sanitizeLabelValue(author)
	}

	releasePlan := &releaseApi.ReleasePlan{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    labels,
		},
		Spec: releaseApi.ReleasePlanSpec{
			Application: appName,
			Target:      targetNamespace,
		},
	}

	err := f.AsKubeDeveloper.ReleaseController.KubeRest().Create(context.Background(), releasePlan)
	if err != nil {
		return "", fmt.Errorf("unable to create the releasePlan %s in %s: %v", name, namespace, err)
	}

	return name, nil
}

// Delete an existing ReleasePlanAdmission with the given name (if any) and wait until it is fully removed,
// so a subsequent create with the same name cannot fail with AlreadyExists.
func deleteReleasePlanAdmissionIfPresent(f *framework.Framework, name, namespace string) error {
	logging.Logger.Debug("Checking whether release plan admission %s in namespace %s already exists", name, namespace)

	existing, err := f.AsKubeDeveloper.ReleaseController.GetReleasePlanAdmission(name, namespace)
	if err != nil {
		if k8serrors.IsNotFound(err) {
			return nil
		}
		return fmt.Errorf("unable to get the releasePlanAdmission %s in %s: %v", name, namespace, err)
	}

	if existing.DeletionTimestamp == nil {
		logging.Logger.Info("Deleting existing release plan admission %s in namespace %s before creating a fresh one", name, namespace)
		err = f.AsKubeDeveloper.ReleaseController.DeleteReleasePlanAdmission(name, namespace, false)
		if err != nil {
			return fmt.Errorf("unable to delete the releasePlanAdmission %s in %s: %v", name, namespace, err)
		}
	}

	// Wait for the object to be gone so the subsequent create cannot race with the deletion
	err = utils.WaitUntilWithInterval(func() (done bool, err error) {
		_, err = f.AsKubeDeveloper.ReleaseController.GetReleasePlanAdmission(name, namespace)
		if err != nil && k8serrors.IsNotFound(err) {
			return true, nil
		}
		return false, nil
	}, time.Second*2, time.Minute*2)
	if err != nil {
		return fmt.Errorf("timed out waiting for releasePlanAdmission %s in %s to be deleted: %v", name, namespace, err)
	}

	return nil
}

// Create ReleasePlanAdmission CR
// Assumes enterprise contract policy and service account with required permissions is already there
// Idempotent: if an RPA with the same name already exists, delete it first and create a fresh one
func createReleasePlanAdmission(f *framework.Framework, namespace, originNamespace, appName, policyName, releasePipelineSAName, releasePipelineUrl, releasePipelineRevision, releasePipelinePath string, releaseOciStorage string, data *runtime.RawExtension) (string, error) {
	name := appName + "-rpa"
	logging.Logger.Debug("Creating release plan admission %s in namespace %s with origin %s, policy %s and pipeline SA %s", name, namespace, originNamespace, policyName, releasePipelineSAName)

	err := deleteReleasePlanAdmissionIfPresent(f, name, namespace)
	if err != nil {
		return "", err
	}

	_, err = f.AsKubeDeveloper.ReleaseController.CreateReleasePlanAdmissionWithGitPipeline(name, namespace, originNamespace, policyName, releasePipelineSAName, []string{appName}, true, releasePipelineUrl, releasePipelineRevision, releasePipelinePath, releaseOciStorage, data)
	if err != nil {
		if k8serrors.IsAlreadyExists(err) {
			// Raced with another creation attempt: delete and try to create again
			if delErr := deleteReleasePlanAdmissionIfPresent(f, name, namespace); delErr != nil {
				return "", delErr
			}
			_, err = f.AsKubeDeveloper.ReleaseController.CreateReleasePlanAdmissionWithGitPipeline(name, namespace, originNamespace, policyName, releasePipelineSAName, []string{appName}, true, releasePipelineUrl, releasePipelineRevision, releasePipelinePath, releaseOciStorage, data)
		}
		if err != nil {
			return "", fmt.Errorf("unable to create the releasePlanAdmission %s in %s: %v", name, namespace, err)
		}
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

// Validate a pre-existing, releng-owned ReleasePlanAdmission instead of
// creating one. Used when --release-managed-readonly is set.
func setupReadOnlyReleasePlanAdmission(ctx *types.PerApplicationContext, rpaFramework *framework.Framework, rpaNamespace string) error {
	var err error

	ctx.ReleasePlanAdmissionName = ctx.ParentContext.Opts.ReleaseManagedReleasePlanAdmissionName

	_, err = logging.Measure(
		ctx,
		validateReleasePlan,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ReleasePlanName,
	)
	if err != nil {
		return logging.Logger.Fail(120, "Release Plan failed validation: %v", err)
	}

	_, err = logging.Measure(
		ctx,
		validateReleasePlanAdmission,
		rpaFramework,
		rpaNamespace,
		ctx.ReleasePlanAdmissionName,
	)
	if err != nil {
		return logging.Logger.Fail(121, "Pre-existing Release Plan Admission %s in read-only managed namespace %s failed validation: %v", ctx.ReleasePlanAdmissionName, rpaNamespace, err)
	}

	logging.Logger.Info("Configured release %s & pre-existing %s for application %s in namespace %s (RPA in %s)", ctx.ReleasePlanName, ctx.ReleasePlanAdmissionName, ctx.ApplicationName, ctx.ParentContext.Namespace, rpaNamespace)

	return nil
}

// Create, and validate a ReleasePlanAdmission owned by this run. This is the
// default behavior (i.e. --release-managed-readonly is not set).
func setupReadWriteReleasePlanAdmission(ctx *types.PerApplicationContext, rpaFramework *framework.Framework, rpaNamespace string) error {
	var iface interface{}
	var ok bool
	var err error

	var rpaData *runtime.RawExtension
	if ctx.ParentContext.Opts.ReleasePlanAdmissionDataPath != "" {
		dataBytes, err := os.ReadFile(ctx.ParentContext.Opts.ReleasePlanAdmissionDataPath)
		if err != nil {
			return logging.Logger.Fail(97, "Failed to read RPA data file %s: %v", ctx.ParentContext.Opts.ReleasePlanAdmissionDataPath, err)
		}
		var dataMap map[string]interface{}
		if err := json.Unmarshal(dataBytes, &dataMap); err != nil {
			return logging.Logger.Fail(98, "Failed to parse RPA data JSON: %v", err)
		}
		componentNames := make([]map[string]string, ctx.ParentContext.Opts.ComponentsCount)
		for i := 0; i < ctx.ParentContext.Opts.ComponentsCount; i++ {
			componentNames[i] = map[string]string{"name": fmt.Sprintf("%s-comp-%d", ctx.ApplicationName, i)}
		}
		if mapping, ok := dataMap["mapping"].(map[string]interface{}); ok {
			mapping["components"] = componentNames
		} else {
			dataMap["mapping"] = map[string]interface{}{"components": componentNames}
		}
		dataBytes, err = json.Marshal(dataMap)
		if err != nil {
			return logging.Logger.Fail(99, "Failed to marshal RPA data: %v", err)
		}
		rpaData = &runtime.RawExtension{Raw: dataBytes}
	}

	iface, err = logging.Measure(
		ctx,
		createReleasePlanAdmission,
		rpaFramework,
		rpaNamespace,
		ctx.ParentContext.Namespace,
		ctx.ApplicationName,
		ctx.ParentContext.Opts.ReleasePolicy,
		ctx.ParentContext.Opts.ReleasePipelineServiceAccount,
		ctx.ParentContext.Opts.ReleasePipelineUrl,
		ctx.ParentContext.Opts.ReleasePipelineRevision,
		ctx.ParentContext.Opts.ReleasePipelinePath,
		ctx.ParentContext.Opts.ReleaseOciStorage,
		rpaData,
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
		rpaFramework,
		rpaNamespace,
		ctx.ReleasePlanAdmissionName,
	)
	if err != nil {
		return logging.Logger.Fail(96, "Release Plan Admission failed validation: %v", err)
	}

	logging.Logger.Info("Configured release %s & %s for application %s in namespace %s (RPA in %s)", ctx.ReleasePlanName, ctx.ReleasePlanAdmissionName, ctx.ApplicationName, ctx.ParentContext.Namespace, rpaNamespace)

	return nil
}

// HandleReleaseSetup creates release plans and admissions for an application.
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

	// Compute framework/namespace routing for managed namespace mode
	rpaFramework := ctx.Framework
	rpaNamespace := ctx.ParentContext.Namespace
	rpTargetNamespace := ctx.ParentContext.Namespace

	if ctx.ParentContext.Opts.ReleaseManagedNamespace != "" {
		rpaFramework = ctx.ManagedFramework
		rpaNamespace = ctx.ParentContext.Opts.ReleaseManagedNamespace
		rpTargetNamespace = ctx.ParentContext.Opts.ReleaseManagedNamespace
	}

	iface, err := logging.Measure(
		ctx,
		createReleasePlan,
		ctx.Framework,
		ctx.ParentContext.Namespace,
		ctx.ApplicationName,
		rpTargetNamespace,
		ctx.ParentContext.Opts.ReleaseAuthor,
	)
	if err != nil {
		return logging.Logger.Fail(91, "Release Plan failed creation: %v", err)
	}

	ok := false
	ctx.ReleasePlanName, ok = iface.(string)
	if !ok {
		return logging.Logger.Fail(92, "Type assertion failed on release plan name: %+v", iface)
	}

	if ctx.ParentContext.Opts.ReleaseManagedReadOnly {
		return setupReadOnlyReleasePlanAdmission(ctx, rpaFramework, rpaNamespace)
	}
	return setupReadWriteReleasePlanAdmission(ctx, rpaFramework, rpaNamespace)
}
