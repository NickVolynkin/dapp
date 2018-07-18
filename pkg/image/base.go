package image

import (
	"fmt"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
	"golang.org/x/net/context"
)

type Base struct {
	Ref     string
	Inspect *types.ImageInspect
}

func NewBaseImage(ref string) *Base {
	image := &Base{}
	image.Ref = ref
	return image
}

func (i *Base) Id() string {
	if i.Inspect != nil {
		return i.Inspect.ID
	} else {
		panic(fmt.Sprintf("image %s not exist", i.Ref))
	}
}

func (i *Base) ResetInspect(dockerApiClient *client.Client) error {
	inspect, err := inspect(dockerApiClient, i.Ref)
	if err != nil {
		return err
	}

	i.Inspect = inspect
	return nil
}

func inspect(dockerApiClient *client.Client, imageId string) (*types.ImageInspect, error) {
	ctx := context.Background()
	inspect, _, err := dockerApiClient.ImageInspectWithRaw(ctx, imageId)
	if err != nil {
		if client.IsErrNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("stage inspect failed: %s", err)
	}
	return &inspect, nil
}
