package journey

import (
	"context"
	"fmt"
	"strings"

	logging "github.com/konflux-ci/loadtest/pkg/logging"

	"github.com/google/go-github/v66/github"
	"github.com/konflux-ci/e2e-tests/pkg/constants"
	framework "github.com/konflux-ci/e2e-tests/pkg/framework"
	"github.com/konflux-ci/e2e-tests/pkg/utils"
	"golang.org/x/oauth2"
)

const pacOkToTestComment = "/ok-to-test"

func pacOkToTestCommentBody(commitSHA string) string {
	if commitSHA == "" {
		return pacOkToTestComment
	}
	return fmt.Sprintf("%s %s", pacOkToTestComment, commitSHA)
}

func isPacOkToTestComment(body, commitSHA string) bool {
	body = strings.TrimSpace(body)
	expected := pacOkToTestCommentBody(commitSHA)
	if body == expected {
		return true
	}
	if commitSHA == "" {
		return body == pacOkToTestComment
	}
	if !strings.HasPrefix(body, pacOkToTestComment+" ") {
		return false
	}
	fields := strings.Fields(body)
	if len(fields) < 2 {
		return false
	}
	commentedSHA := fields[1]
	return strings.HasPrefix(commitSHA, commentedSHA) || strings.HasPrefix(commentedSHA, commitSHA)
}

// Authorize PaC to run pipelines for fork repos. With remember-ok-to-test disabled on
// the cluster, authorization does not carry over to new commits — post this after the
// LWPython template push commit, not after the onboarding PR merge.
func ensurePaCOkToTest(f *framework.Framework, repoUrl string, prNumber int, commitSHA string) error {
	if strings.Contains(repoUrl, "gitlab.") {
		return nil
	}

	repoName, err := getRepoNameFromRepoUrl(repoUrl)
	if err != nil {
		return err
	}

	repoOrg, err := getRepoOrgFromRepoUrl(repoUrl)
	if err != nil {
		return err
	}

	commentBody := pacOkToTestCommentBody(commitSHA)

	comments, err := listGitHubIssueComments(repoOrg, repoName, prNumber)
	if err != nil {
		return fmt.Errorf("listing PR %d comments on %s: %w", prNumber, repoUrl, err)
	}
	for _, comment := range comments {
		if isPacOkToTestComment(comment.GetBody(), commitSHA) {
			logging.Logger.Debug("PR %d on %s already has %s for commit %s", prNumber, repoUrl, pacOkToTestComment, commitSHA)
			return nil
		}
	}

	logging.Logger.Info("Posting %s on PR %d (%s/%s) to authorize PaC", commentBody, prNumber, repoOrg, repoName)
	if err := postGitHubIssueComment(repoOrg, repoName, prNumber, commentBody); err != nil {
		return fmt.Errorf("posting %s on PR %d: %w", commentBody, prNumber, err)
	}

	return nil
}

func newGitHubClient() (*github.Client, error) {
	token := utils.GetEnv(constants.GITHUB_TOKEN_ENV, "")
	if token == "" {
		return nil, fmt.Errorf("GITHUB_TOKEN is not set")
	}

	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	return github.NewClient(oauth2.NewClient(context.Background(), ts)), nil
}

func listGitHubIssueComments(org, repo string, prNumber int) ([]*github.IssueComment, error) {
	client, err := newGitHubClient()
	if err != nil {
		return nil, err
	}

	comments, _, err := client.Issues.ListComments(
		context.Background(),
		org,
		repo,
		prNumber,
		nil,
	)
	return comments, err
}

func postGitHubIssueComment(org, repo string, prNumber int, body string) error {
	client, err := newGitHubClient()
	if err != nil {
		return err
	}

	_, _, err = client.Issues.CreateComment(
		context.Background(),
		org,
		repo,
		prNumber,
		&github.IssueComment{Body: github.String(body)},
	)
	return err
}
