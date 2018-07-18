package image

import (
	"fmt"

	"github.com/docker/cli/cli/command"
	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
)

type Stage struct {
	*Base
	From         *Stage
	Container    *StageContainer
	BuiltInspect *types.ImageInspect
}

func NewStageImage(from *Stage, ref string) *Stage {
	stage := &Stage{}
	stage.Base = NewBaseImage(ref)
	stage.From = from
	stage.Container = NewStageImageContainer()
	stage.Container.Image = stage
	return stage
}

func (i *Stage) Id() string {
	if i.BuiltInspect != nil {
		return i.BuiltInspect.ID
	} else {
		return i.Base.Id()
	}
}

func (i *Stage) Build(dockerClient *command.DockerCli, dockerApiClient *client.Client) error {
	if err := i.Container.Run(dockerClient, dockerApiClient); err != nil {
		return fmt.Errorf("stage build failed: %s", err)
	}

	if err := i.Commit(dockerApiClient); err != nil {
		return fmt.Errorf("stage build failed: %s", err)
	}

	if err := i.Container.Rm(dockerApiClient); err != nil {
		return fmt.Errorf("stage build failed: %s", err)
	}

	return nil
}

func (i *Stage) Commit(dockerApiClient *client.Client) error {
	builtId, err := i.Container.Commit(dockerApiClient)
	if err != nil {
		return fmt.Errorf("stage commit failed: %s", err)
	}

	inspect, err := inspect(dockerApiClient, builtId)
	if err != nil {
		return err
	}

	i.BuiltInspect = inspect

	return nil
}

func (i *Stage) Introspect(dockerClient *command.DockerCli, dockerApiClient *client.Client) error {
	if err := i.Container.Introspect(dockerClient, dockerApiClient); err != nil {
		return fmt.Errorf("stage introspect failed: %s", err)
	}

	return nil
}
