/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package test

import (
	"context"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	"github.com/kubernetes-csi/csi-test/pkg/sanity"
	"github.com/rexray/gocsi"
	"github.com/rexray/gocsi/utils"

	"k8s.io/cloud-provider-vsphere/pkg/csi/provider"
	"k8s.io/cloud-provider-vsphere/pkg/csi/types"
)

const (
	udsFile = "csi.sock"
)

func TestCSISanity(t *testing.T) {
	RegisterFailHandler(Fail)
	// Setup the full driver and its environment
	tempDir, err := ioutil.TempDir("", "csi-test")
	if err != nil {
		t.Fatalf("Unable to create tempdir")
	}
	udsPath := filepath.Join(tempDir, udsFile)
	os.Setenv(gocsi.EnvVarEndpoint, udsPath)
	os.Setenv(types.EnvDisableK8sClient, "true")
	fmt.Fprintf(w, "socket file at: %s\n", udsPath)
	sp := provider.New()
	stopSrv := startSP(sp)

	defer func() {
		stopSrv()
		os.RemoveAll(tempDir)
		os.Unsetenv(gocsi.EnvVarEndpoint)
	}()

	config := &sanity.Config{
		Address: udsPath,
	}

	sanity.Test(t, config)
}

/*
var _ = Describe("SanityTests", func() {

	var (
		udsPath string
		config  *sanity.Config
		stopSrv func()
		sp      gocsi.StoragePluginProvider
	)

	BeforeEach(func() {
		udsPath = filepath.Join(tempDir, udsFile)
		config = &sanity.Config{
			Address: udsPath,
		}
		os.Setenv(gocsi.EnvVarEndpoint, udsPath)
		fmt.Fprintf(w, "socket file at: %s\n", udsPath)
		sp = provider.New()
		stopSrv = startSP(sp)
	})

	AfterEach(func() {
		stopSrv()
		os.RemoveAll(udsPath)
		os.Unsetenv(gocsi.EnvVarEndpoint)
	})

	Describe("CSI sanity", func() {
		sanity.GinkgoTest(config)
	})
})

*/

// startSP serves the given SP
func startSP(sp gocsi.StoragePluginProvider) func() {

	ctx := context.Background()
	lis, err := utils.GetCSIEndpointListener()
	Ω(err).ShouldNot(HaveOccurred())

	go func() {
		defer GinkgoRecover()
		if err := sp.Serve(ctx, lis); err != nil {
			Ω(err.Error()).Should(Equal("http: Server closed"))
		}
	}()

	return func() { sp.GracefulStop(ctx) }
}
