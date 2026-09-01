package journey

import "fmt"

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

import framework "github.com/konflux-ci/e2e-tests/pkg/framework"
import k8s_api_errors "k8s.io/apimachinery/pkg/api/errors"

func imageRepositoryNameForComponent(compName string) string {
	return compName + "-image"
}

func createImageRepository(f *framework.Framework, namespace, appName, compName string) (string, error) {
	imageRepoName := imageRepositoryNameForComponent(compName)
	logging.Logger.Debug("Creating ImageRepository %s in namespace %s", imageRepoName, namespace)

	_, err := f.AsKubeDeveloper.ImageController.CreateImageRepositoryCR(imageRepoName, namespace, "public", "", appName, compName, true)
	if err != nil {
		return "", fmt.Errorf("unable to create ImageRepository %s: %v", imageRepoName, err)
	}

	return imageRepoName, nil
}

func waitForImageRepositoryReady(f *framework.Framework, namespace, imageRepoName string) error {
	logging.Logger.Debug("Waiting for ImageRepository %s in namespace %s to be ready", imageRepoName, namespace)

	err := f.AsKubeDeveloper.ImageController.WaitForImageRepositoryToBeReady(imageRepoName, namespace)
	if err != nil {
		return fmt.Errorf("ImageRepository %s in namespace %s not ready: %v", imageRepoName, namespace, err)
	}

	return nil
}

func deleteImageRepository(f *framework.Framework, namespace, imageRepoName string) error {
	if err := f.AsKubeDeveloper.ImageController.DeleteImageRepositoryCR(imageRepoName, namespace); err != nil {
		if k8s_api_errors.IsNotFound(err) {
			logging.Logger.Debug("ImageRepository %s not found in namespace %s, skipping", imageRepoName, namespace)
			return nil
		}
		return fmt.Errorf("failed to delete ImageRepository %s in namespace %s: %w", imageRepoName, namespace, err)
	}
	logging.Logger.Debug("Deleted ImageRepository %s in namespace %s", imageRepoName, namespace)
	return nil
}

// HandleImageRepository creates or reuses an ImageRepository CR for a component.
func HandleImageRepository(ctx *types.PerComponentContext) error {
	var iface interface{}
	var ok bool
	var err error

	iface, err = logging.Measure(
		ctx,
		createImageRepository,
		ctx.Framework,
		ctx.ParentContext.ParentContext.Namespace,
		ctx.ParentContext.ApplicationName,
		ctx.ComponentName,
	)
	if err != nil {
		return logging.Logger.Fail(50, "ImageRepository creation failed: %v", err)
	}

	imageRepoName, ok := iface.(string)
	if !ok {
		return logging.Logger.Fail(51, "Type assertion failed on ImageRepository name: %+v", iface)
	}

	_, err = logging.Measure(
		ctx,
		waitForImageRepositoryReady,
		ctx.Framework,
		ctx.ParentContext.ParentContext.Namespace,
		imageRepoName,
	)
	if err != nil {
		return logging.Logger.Fail(52, "ImageRepository failed to become ready: %v", err)
	}

	return nil
}
