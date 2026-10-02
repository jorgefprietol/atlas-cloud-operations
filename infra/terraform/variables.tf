variable "region" {
  type    = string
  default = "us-east-1"
}
variable "name" {
  type    = string
  default = "atlas"
}
variable "environment" {
  type    = string
  default = "production"
}
variable "github_repository" {
  type    = string
  default = "jorgefprietol/atlas-cloud-operations"
}
variable "api_domain" {
  type        = string
  description = "DNS hostname for the ALB origin, e.g. api-atlas.example.com"
}
variable "route53_zone_id" {
  type = string
}
variable "alb_certificate_arn" {
  type        = string
  description = "Validated ACM certificate in the selected region matching api_domain"
}
variable "api_image" {
  type        = string
  description = "Immutable ECR image reference with @sha256 digest"
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.api_image))
    error_message = "api_image must reference an immutable SHA256 digest."
  }
}
variable "worker_image" {
  type = string
  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.worker_image))
    error_message = "worker_image must reference an immutable SHA256 digest."
  }
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "enable_guardduty" {
  type        = bool
  default     = false
  description = "Enable only when no organization-managed detector exists in this region"
}
variable "github_oidc_provider_arn" {
  type        = string
  description = "Existing IAM OIDC provider for token.actions.githubusercontent.com"
}
