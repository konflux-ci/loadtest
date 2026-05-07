//go:build ignore

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"time"

	framework "github.com/konflux-ci/e2e-tests/pkg/framework"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	schema "k8s.io/apimachinery/pkg/runtime/schema"
	watch "k8s.io/apimachinery/pkg/watch"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: go run watch-experiment.go <username> <namespace>\n")
		fmt.Fprintf(os.Stderr, "\nThis uses the same framework.NewFrameworkWithTimeout() as loadtest.\n")
		fmt.Fprintf(os.Stderr, "Username is e.g. your SSO username, namespace is the tenant namespace.\n")
		os.Exit(1)
	}
	username := os.Args[1]
	namespace := os.Args[2]

	fmt.Printf("Provisioning framework for user %s...\n", username)
	f, err := framework.NewFrameworkWithTimeout(username, time.Minute*5)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create framework: %v\n", err)
		os.Exit(1)
	}

	gvr := schema.GroupVersionResource{
		Group:    "appstudio.redhat.com",
		Version:  "v1alpha1",
		Resource: "components",
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	fmt.Printf("Starting watch on components in namespace %s (Ctrl+C to stop)...\n\n", namespace)

	watcher, err := f.AsKubeDeveloper.CommonController.DynamicClient().
		Resource(gvr).
		Namespace(namespace).
		Watch(ctx, metav1.ListOptions{})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create watcher: %v\n", err)
		os.Exit(1)
	}
	defer watcher.Stop()

	for {
		select {
		case <-ctx.Done():
			fmt.Println("\nStopping watch.")
			return
		case event, ok := <-watcher.ResultChan():
			if !ok {
				fmt.Println("Watch channel closed.")
				return
			}
			printEvent(event)
		}
	}
}

func printEvent(event watch.Event) {
	obj, ok := event.Object.(*unstructured.Unstructured)
	if !ok {
		fmt.Printf("[%s] non-unstructured object: %T\n", event.Type, event.Object)
		return
	}

	name := obj.GetName()
	generation := obj.GetGeneration()
	rv := obj.GetResourceVersion()

	fmt.Printf("[%s] component=%s generation=%d resourceVersion=%s\n",
		event.Type, name, generation, rv)

	// Print conditions if present
	conditions, found, _ := unstructured.NestedSlice(obj.Object, "status", "conditions")
	if found {
		for _, c := range conditions {
			cond, ok := c.(map[string]interface{})
			if !ok {
				continue
			}
			fmt.Printf("  condition: type=%s status=%s reason=%s\n",
				cond["type"], cond["status"], cond["reason"])
		}
	}

	// Print selected annotations
	annotations := obj.GetAnnotations()
	for _, key := range []string{
		"build.appstudio.openshift.io/request",
		"build.appstudio.openshift.io/status",
	} {
		if val, exists := annotations[key]; exists {
			// Pretty-print JSON annotations
			var parsed interface{}
			if json.Unmarshal([]byte(val), &parsed) == nil {
				pretty, _ := json.MarshalIndent(parsed, "    ", "  ")
				fmt.Printf("  annotation %s:\n    %s\n", key, pretty)
			} else {
				fmt.Printf("  annotation %s: %s\n", key, val)
			}
		}
	}

	fmt.Println()
}
