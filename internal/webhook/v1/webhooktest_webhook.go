/*
Copyright 2025.

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

package v1

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/validation/field"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"

	webhookv1 "github.com/perdasilva/webhook-operator/api/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
)

// nolint:unused
// log is for logging in this package.
var webhooktestlog = logf.Log.WithName("webhooktest-resource")

// SetupWebhookTestWebhookWithManager registers the webhook for WebhookTest in the manager.
func SetupWebhookTestWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).For(&webhookv1.WebhookTest{}).
		WithValidator(&WebhookTestCustomValidator{}).
		WithDefaulter(&WebhookTestCustomDefaulter{}).
		Complete()
}

// TODO(user): EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!

// +kubebuilder:webhook:path=/mutate-webhook-operators-coreos-io-v1-webhooktest,mutating=true,failurePolicy=fail,sideEffects=None,groups=webhook.operators.coreos.io,resources=webhooktests,verbs=create;update,versions=v1,name=mwebhooktest-v1.kb.io,admissionReviewVersions=v1

// WebhookTestCustomDefaulter struct is responsible for setting default values on the custom resource of the
// Kind WebhookTest when those are created or updated.
//
// NOTE: The +kubebuilder:object:generate=false marker prevents controller-gen from generating DeepCopy methods,
// as it is used only for temporary operations and does not need to be deeply copied.
type WebhookTestCustomDefaulter struct {
	// TODO(user): Add more fields as needed for defaulting
}

var _ webhook.CustomDefaulter = &WebhookTestCustomDefaulter{}

// Default implements webhook.CustomDefaulter so a webhook will be registered for the Kind WebhookTest.
func (d *WebhookTestCustomDefaulter) Default(_ context.Context, obj runtime.Object) error {
	webhooktest, ok := obj.(*webhookv1.WebhookTest)

	if !ok {
		return fmt.Errorf("expected an WebhookTest object but got %T", obj)
	}
	webhooktestlog.Info("Defaulting for WebhookTest", "name", webhooktest.GetName())

	if !webhooktest.Spec.Mutate {
		webhooktest.Spec.Mutate = true
	}

	return nil
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
// NOTE: The 'path' attribute must follow a specific pattern and should not be modified directly here.
// Modifying the path for an invalid path can cause API server errors; failing to locate the webhook.
// +kubebuilder:webhook:path=/validate-webhook-operators-coreos-io-v1-webhooktest,mutating=false,failurePolicy=fail,sideEffects=None,groups=webhook.operators.coreos.io,resources=webhooktests,verbs=create;update,versions=v1,name=vwebhooktest-v1.kb.io,admissionReviewVersions=v1

// WebhookTestCustomValidator struct is responsible for validating the WebhookTest resource
// when it is created, updated, or deleted.
//
// NOTE: The +kubebuilder:object:generate=false marker prevents controller-gen from generating DeepCopy methods,
// as this struct is used only for temporary operations and does not need to be deeply copied.
type WebhookTestCustomValidator struct {
	// TODO(user): Add more fields as needed for validation
}

var _ webhook.CustomValidator = &WebhookTestCustomValidator{}

// ValidateCreate implements webhook.CustomValidator so a webhook will be registered for the type WebhookTest.
func (v *WebhookTestCustomValidator) ValidateCreate(_ context.Context, obj runtime.Object) (admission.Warnings, error) {
	webhooktest, ok := obj.(*webhookv1.WebhookTest)
	if !ok {
		return nil, fmt.Errorf("expected a WebhookTest object but got %T", obj)
	}
	webhooktestlog.Info("Validation for WebhookTest upon creation", "name", webhooktest.GetName())
	return nil, v.validateWebhookTest(webhooktest)
}

// ValidateUpdate implements webhook.CustomValidator so a webhook will be registered for the type WebhookTest.
func (v *WebhookTestCustomValidator) ValidateUpdate(_ context.Context, oldObj, newObj runtime.Object) (admission.Warnings, error) {
	webhooktest, ok := newObj.(*webhookv1.WebhookTest)
	if !ok {
		return nil, fmt.Errorf("expected a WebhookTest object for the newObj but got %T", newObj)
	}
	webhooktestlog.Info("Validation for WebhookTest upon update", "name", webhooktest.GetName())
	return nil, v.validateWebhookTest(webhooktest)
}

// ValidateDelete implements webhook.CustomValidator so a webhook will be registered for the type WebhookTest.
func (v *WebhookTestCustomValidator) ValidateDelete(ctx context.Context, obj runtime.Object) (admission.Warnings, error) {
	webhooktest, ok := obj.(*webhookv1.WebhookTest)
	if !ok {
		return nil, fmt.Errorf("expected a WebhookTest object but got %T", obj)
	}
	webhooktestlog.Info("Validation for WebhookTest upon deletion", "name", webhooktest.GetName())

	// TODO(user): fill in your validation logic upon object deletion.

	return nil, nil
}

func (v *WebhookTestCustomValidator) validateWebhookTest(r *webhookv1.WebhookTest) error {
	var allErrs field.ErrorList
	if !r.Spec.Valid {
		allErrs = append(allErrs, field.Invalid(field.NewPath("spec").Child("schedule"), r.Spec.Valid, "Spec.Valid must be true"))
	}

	if len(allErrs) != 0 {
		return apierrors.NewInvalid(
			schema.GroupKind{Group: "test.operators.coreos.com", Kind: "WebhookTest"},
			r.Name, allErrs)
	}

	return nil
}
