# Plan: e2e-tests changes to let loadtest drop direct dependencies

This document describes changes needed in [github.com/konflux-ci/e2e-tests](https://github.com/konflux-ci/e2e-tests)
to allow loadtest to remove its direct dependencies on `application-api` and `release-service`.
Once PRs are merged in e2e-tests and loadtest bumps the dependency, the simplifications
described in "loadtest follow-up" sections can be applied.

## 1. Drop `github.com/konflux-ci/application-api`

### Current situation in loadtest

Loadtest imports `application-api` in 2 files:

**`handle_component.go`** — constructs `appstudioApi.ComponentSpec` to pass to
`HasController.CreateComponent()`:

```go
componentObj := appstudioApi.ComponentSpec{
    ComponentName: name,
    Source: appstudioApi.ComponentSource{
        ComponentSourceUnion: appstudioApi.ComponentSourceUnion{
            GitSource: &appstudioApi.GitSource{
                URL:           repoUrl,
                Revision:      repoRevision,
                Context:       containerContext,
                DockerfileURL: containerFile,
            },
        },
    },
}
_, err := f.AsKubeDeveloper.HasController.CreateComponent(componentObj, namespace, "", "", appName, false, annotationsMap)
```

**`handle_test_run.go`** — uses `*appstudioApi.Snapshot` as variable type for
`IntegrationController.GetSnapshot()` return value (accesses `.Name`).

### What to add in e2e-tests

Add a convenience method to `HasController` in `pkg/clients/has/components.go`:

```go
// CreateComponentFromGitSource creates a Component from a Git repository without
// requiring callers to construct ComponentSpec directly.
func (h *HasController) CreateComponentFromGitSource(
    name, namespace, appName string,
    gitURL, revision, context, dockerfileURL string,
    skipInitialChecks bool,
    annotations map[string]string,
) (*appservice.Component, error) {
    spec := appservice.ComponentSpec{
        ComponentName: name,
        Source: appservice.ComponentSource{
            ComponentSourceUnion: appservice.ComponentSourceUnion{
                GitSource: &appservice.GitSource{
                    URL:           gitURL,
                    Revision:      revision,
                    Context:       context,
                    DockerfileURL: dockerfileURL,
                },
            },
        },
    }
    return h.CreateComponent(spec, namespace, "", "", appName, skipInitialChecks, annotations)
}
```

### Loadtest follow-up

- **`handle_component.go`**: Replace `CreateComponent(componentObj, ...)` call with
  `CreateComponentFromGitSource(name, namespace, appName, repoUrl, ...)`. Remove the
  `appstudioApi` import entirely.
- **`handle_test_run.go`**: The `GetSnapshot()` return is `*appstudioApi.Snapshot` which
  embeds standard `metav1.ObjectMeta`. After removing the other usage, we can just use
  `:=` and access `.Name` — Go infers the type. Remove the import.
- Run `go mod tidy` — `application-api` will move to indirect.


## 2. Drop `github.com/konflux-ci/release-service`

### Current situation in loadtest

Loadtest imports `release-service` in 1 file:

**`handle_releases_setup.go`** — uses:

1. `tektonutils.PipelineRef` and `tektonutils.Param` to construct the pipeline reference
   passed to `ReleaseController.CreateReleasePlanAdmission()`:

   ```go
   pipeline := &tektonutils.PipelineRef{
       Resolver: "git",
       Params: []tektonutils.Param{
           {Name: "url", Value: releasePipelineUrl},
           {Name: "revision", Value: releasePipelineRevision},
           {Name: "pathInRepo", Value: releasePipelinePath},
       },
       OciStorage: releaseOciStorage,
   }
   _, err := f.AsKubeDeveloper.ReleaseController.CreateReleasePlanAdmission(
       name, namespace, "", namespace, policyName, releasePipelineSAName,
       []string{appName}, true, pipeline, nil,
   )
   ```

2. `releaseApi.MatchedConditionType` and `releaseApi.MatchedReason` — string constants
   (both resolve to `"Matched"`) used to check ReleasePlan/ReleasePlanAdmission status
   conditions.

### What to add in e2e-tests

#### 2a. Convenience wrapper for creating RPA with git pipeline

Add to `ReleaseController` in `pkg/clients/release/plans.go`:

```go
// CreateReleasePlanAdmissionWithGitPipeline creates a ReleasePlanAdmission with a
// git-resolver based pipeline, without requiring callers to construct PipelineRef.
func (r *ReleaseController) CreateReleasePlanAdmissionWithGitPipeline(
    name, namespace, origin, policy, serviceAccountName string,
    applications []string, blockReleases bool,
    pipelineUrl, pipelineRevision, pipelinePath, ociStorage string,
    data *runtime.RawExtension,
) (*releaseApi.ReleasePlanAdmission, error) {
    pipelineRef := &tektonutils.PipelineRef{
        Resolver: "git",
        Params: []tektonutils.Param{
            {Name: "url", Value: pipelineUrl},
            {Name: "revision", Value: pipelineRevision},
            {Name: "pathInRepo", Value: pipelinePath},
        },
        OciStorage: ociStorage,
    }
    return r.CreateReleasePlanAdmission(
        name, namespace, "", origin, policy, serviceAccountName,
        applications, blockReleases, pipelineRef, data,
    )
}
```

#### 2b. Condition check helpers

Add to `ReleaseController` in `pkg/clients/release/plans.go`:

```go
// IsReleasePlanMatched returns true if the ReleasePlan has a Matched condition
// with status True and reason Matched.
func (r *ReleaseController) IsReleasePlanMatched(releasePlan *releaseApi.ReleasePlan) bool {
    condition := meta.FindStatusCondition(
        releasePlan.Status.Conditions,
        releaseApi.MatchedConditionType.String(),
    )
    return condition != nil &&
        condition.Status == metav1.ConditionTrue &&
        condition.Reason == releaseApi.MatchedReason.String()
}

// IsReleasePlanAdmissionMatched returns true if the ReleasePlanAdmission has a
// Matched condition with status True and reason Matched.
func (r *ReleaseController) IsReleasePlanAdmissionMatched(rpa *releaseApi.ReleasePlanAdmission) bool {
    condition := meta.FindStatusCondition(
        rpa.Status.Conditions,
        releaseApi.MatchedConditionType.String(),
    )
    return condition != nil &&
        condition.Status == metav1.ConditionTrue &&
        condition.Reason == releaseApi.MatchedReason.String()
}

// GetReleasePlanMatchedCondition returns the Matched condition from a ReleasePlan,
// or nil if not yet set. Useful when callers need to inspect reason/status details.
func (r *ReleaseController) GetReleasePlanMatchedCondition(releasePlan *releaseApi.ReleasePlan) *metav1.Condition {
    return meta.FindStatusCondition(
        releasePlan.Status.Conditions,
        releaseApi.MatchedConditionType.String(),
    )
}

// GetReleasePlanAdmissionMatchedCondition returns the Matched condition from a
// ReleasePlanAdmission, or nil if not yet set.
func (r *ReleaseController) GetReleasePlanAdmissionMatchedCondition(rpa *releaseApi.ReleasePlanAdmission) *metav1.Condition {
    return meta.FindStatusCondition(
        rpa.Status.Conditions,
        releaseApi.MatchedConditionType.String(),
    )
}
```

### Loadtest follow-up

- **`handle_releases_setup.go`**: Replace `CreateReleasePlanAdmission(...)` with
  `CreateReleasePlanAdmissionWithGitPipeline(...)`. Replace condition checking code
  with `GetReleasePlanMatchedCondition()` / `GetReleasePlanAdmissionMatchedCondition()`.
  Remove both `releaseApi` and `tektonutils` imports.
- Run `go mod tidy` — `release-service` will move to indirect.
