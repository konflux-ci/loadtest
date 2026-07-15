package journey

import "fmt"

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

import framework "github.com/konflux-ci/e2e-tests/pkg/framework"

func createImageRepository(f *framework.Framework, namespace, appName, compName string) (string, error) {
	imageRepoName := compName + "-image"
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
