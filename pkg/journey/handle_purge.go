package journey

import "fmt"

import logging "github.com/konflux-ci/loadtest/pkg/logging"
import types "github.com/konflux-ci/loadtest/pkg/types"

import framework "github.com/konflux-ci/e2e-tests/pkg/framework"

func purgeStage(f *framework.Framework, namespace string, appContexts []*types.PerApplicationContext) error {
	if len(appContexts) == 0 {
		logging.Logger.Debug("No application contexts to purge in namespace %s, skipping", namespace)
		return nil
	}

	for _, appCtx := range appContexts {
		if appCtx.ApplicationName == "" {
			continue
		}

		logging.Logger.Debug("Purging application %s in namespace %s", appCtx.ApplicationName, namespace)

		err := f.AsKubeDeveloper.HasController.DeleteApplication(appCtx.ApplicationName, namespace, false)
		if err != nil {
			return fmt.Errorf("error when deleting application %s in namespace %s: %v", appCtx.ApplicationName, namespace, err)
		}

		for _, compCtx := range appCtx.PerComponentContexts {
			if compCtx.ComponentName == "" {
				continue
			}

			err = f.AsKubeDeveloper.HasController.DeleteComponent(compCtx.ComponentName, namespace, false)
			if err != nil {
				return fmt.Errorf("error when deleting component %s in namespace %s: %v", compCtx.ComponentName, namespace, err)
			}
		}
	}

	logging.Logger.Debug("Finished purging namespace %s", namespace)
	return nil
}

func purgeCi(f *framework.Framework, username string) error {
	err := f.AsKubeAdmin.CommonController.DeleteNamespace(f.UserNamespace)
	if err != nil {
		return fmt.Errorf("error when deleting namespace %s for user %s: %v", f.UserNamespace, username, err)
	}

	logging.Logger.Debug("Finished purging namespace %s for user %s", f.UserNamespace, username)
	return nil
}

func Purge() error {
	if !PerUserContexts[0].Opts.Purge {
		return nil
	}

	errCounter := 0

	for _, ctx := range PerUserContexts {
		if ctx.Opts.Stage {
			err := purgeStage(ctx.Framework, ctx.Namespace, ctx.PerApplicationContexts)
			if err != nil {
				logging.Logger.Error("Error when purging Stage: %v", err)
				errCounter++
			}
		} else {
			err := purgeCi(ctx.Framework, ctx.Username)
			if err != nil {
				logging.Logger.Error("Error when purging CI: %v", err)
				errCounter++
			}
		}
	}

	if errCounter > 0 {
		return fmt.Errorf("hit %d errors when purging resources", errCounter)
	} else {
		logging.Logger.Info("No errors when purging resources")
		return nil
	}
}
