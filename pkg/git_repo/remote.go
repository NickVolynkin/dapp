package git_repo

import (
	"fmt"
	"github.com/flant/dapp/pkg/lock"
	"gopkg.in/satori/go.uuid.v1"
	"gopkg.in/src-d/go-git.v4"
	"gopkg.in/src-d/go-git.v4/plumbing"
	"gopkg.in/src-d/go-git.v4/plumbing/storer"
	"os"
	"path/filepath"
	"time"
)

type Remote struct {
	Base
	Url       string
	ClonePath string // TODO: move CacheVersion & path construction here
}

func (repo *Remote) withLock(f func() error) error {
	lockName := fmt.Sprintf("remote_git_artifact.%s", repo.Name)
	return lock.WithLock(lockName, lock.LockOptions{Timeout: 600 * time.Second}, f)
}

func (repo *Remote) isCloneExists() (bool, error) {
	_, err := os.Stat(repo.ClonePath)
	if err == nil {
		return true, nil
	}

	if !os.IsNotExist(err) {
		return false, fmt.Errorf("cannot clone git repo: %s", err)
	}

	return false, nil
}

func (repo *Remote) Clone() error {
	var err error

	exists, err := repo.isCloneExists()
	if err != nil {
		return err
	}
	if exists {
		return nil
	}

	return repo.withLock(func() error {
		exists, err := repo.isCloneExists()
		if err != nil {
			return err
		}
		if exists {
			return nil
		}

		fmt.Printf("Clone remote git repo `%s` ...\n", repo.Url)

		path := filepath.Join("/tmp", fmt.Sprintf("dapp-git-repo-%s", uuid.NewV4().String()))

		_, err = git.PlainClone(path, true, &git.CloneOptions{
			URL:               repo.Url,
			RecurseSubmodules: git.DefaultSubmoduleRecursionDepth,
		})
		if err != nil {
			return fmt.Errorf("cannot clone git repo: %s", err)
		}

		defer os.RemoveAll(path)

		err = os.MkdirAll(filepath.Dir(repo.ClonePath), 0755)
		if err != nil {
			return fmt.Errorf("cannot clone git repo: %s", err)
		}

		err = os.Rename(path, repo.ClonePath)
		if err != nil {
			return fmt.Errorf("cannot clone git repo: %s", err)
		}

		fmt.Printf("Clone remote git repo `%s` DONE\n", repo.Url)

		return nil
	})
}

func (repo *Remote) Fetch() error {
	return nil
}

func (repo *Remote) HeadCommit() (string, error) {
	commit, err := repo.getHeadCommitForRepo(repo.ClonePath)

	if err == nil {
		fmt.Printf("Using HEAD commit `%s` of repository `%s`\n", commit, repo.Url)
	}

	return commit, err
}

func (repo *Remote) findReference(rawRepo *git.Repository, reference string) (string, error) {
	refs, err := rawRepo.References()
	if err != nil {
		return "", err
	}

	var res string

	err = refs.ForEach(func(ref *plumbing.Reference) error {
		if ref.Name().String() == reference {
			res = fmt.Sprintf("%s", ref.Hash())
			return storer.ErrStop
		}

		return nil
	})
	if err != nil {
		return "", err
	}

	return res, nil
}

func (repo *Remote) LatestBranchCommit(branch string) (string, error) {
	var err error

	rawRepo, err := git.PlainOpen(repo.ClonePath)
	if err != nil {
		return "", fmt.Errorf("cannot open repo: %s", err)
	}

	res, err := repo.findReference(rawRepo, fmt.Sprintf("refs/remotes/origin/%s", branch))
	if err != nil {
		return "", err
	}
	if res == "" {
		return "", fmt.Errorf("unknown branch `%s` of repository `%s`", branch, repo.Url)
	}

	fmt.Printf("Using commit `%s` of repository `%s` branch `%s`\n", res, repo.Url, branch)

	return res, nil
}

func (repo *Remote) LatestTagCommit(tag string) (string, error) {
	var err error

	rawRepo, err := git.PlainOpen(repo.ClonePath)
	if err != nil {
		return "", fmt.Errorf("cannot open repo: %s", err)
	}

	res, err := repo.findReference(rawRepo, fmt.Sprintf("refs/tags/%s", tag))
	if err != nil {
		return "", err
	}
	if res == "" {
		return "", fmt.Errorf("unknown tag `%s` of repository `%s`", tag, repo.Url)
	}

	fmt.Printf("Using commit `%s` of repository `%s` tag `%s`\n", res, repo.Url, tag)

	return res, nil
}
