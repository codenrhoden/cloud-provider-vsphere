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
	"fmt"
	"io/ioutil"
	"os"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var (
	tempDir string
	w       = GinkgoWriter
)

/*
func TestCSI(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "CSI Suite")
}*/

var _ = BeforeSuite(func() {
	var err error
	tempDir, err = ioutil.TempDir("", "csi-test")
	Ω(err).ShouldNot(HaveOccurred())
	fmt.Fprintf(w, "created temp dir: %s\n", tempDir)
})

var _ = AfterSuite(func() {
	var err error
	err = os.Remove(tempDir)
	Ω(err).ShouldNot(HaveOccurred())
	fmt.Fprintf(w, "deleted temp dir: %s\n", tempDir)
})
