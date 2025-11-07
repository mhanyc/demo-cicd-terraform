# Terraform Variables for Static Website Infrastructure
# Comprehensive configuration with validation and defaults

# Project Configuration
variable "project_name" {
  description = "Full project name including owner prefix (e.g., 'celtikill-static-site') used for resource naming and IAM policy matching"
  type        = string
  # No default - must be passed from environment configuration

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 50
    error_message = "Project name must be between 3 and 50 characters long."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod, or test environments like integration-test-*, unit-test-*)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment) || can(regex("^(integration-test|unit-test)-[0-9]+", var.environment))
    error_message = "Environment must be dev, staging, prod, or a test environment (integration-test-*, unit-test-*)."
  }
}

variable "github_repository" {
  description = "GitHub repository in format owner/repo"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "GitHub repository must be in format 'owner/repo'."
  }
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region for primary resources"
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "AWS region for cross-region replication"
  type        = string
  default     = "us-west-2"
}

# S3 Configuration
variable "force_destroy_bucket" {
  description = "Allow deletion of non-empty S3 bucket (CAUTION: use only in dev/test)"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_cross_region_replication" {
  description = "Enable S3 cross-region replication"
  type        = bool
  default     = true
}

variable "enable_access_logging" {
  description = "Enable CloudFront access logging to S3"
  type        = bool
  default     = true
}

# CloudFront Configuration
# Feature Flag: CloudFront CDN Distribution
# When disabled: S3-only static website hosting with public bucket policy
# When enabled: Global CDN with Origin Access Control and security headers
# Cost Impact: ~$15-25/month when enabled vs $1-5/month S3-only
variable "enable_cloudfront" {
  description = "Enable CloudFront CDN distribution (feature flag for cost optimization)"
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain (must be in us-east-1)"
  type        = string
  default     = null
}

variable "domain_aliases" {
  description = "List of domain aliases for CloudFront distribution"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for domain in var.domain_aliases : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\\.[a-zA-Z]{2,}$", domain))
    ])
    error_message = "All domain aliases must be valid domain names."
  }
}

variable "geo_restriction_type" {
  description = "CloudFront geo restriction type (none, whitelist, blacklist)"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "Geo restriction type must be none, whitelist, or blacklist."
  }
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restrictions"
  type        = list(string)
  default     = []
}

variable "custom_error_responses" {
  description = "Custom error response configurations"
  type = list(object({
    error_code            = number
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = number
  }))
  default = [
    {
      error_code            = 404
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 300
    },
    {
      error_code            = 403
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 300
    }
  ]
}

variable "content_security_policy" {
  description = "Content Security Policy header value"
  type        = string
  default     = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' https:; connect-src 'self'; frame-ancestors 'none';"
}

variable "cors_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

# WAF Configuration  
# Feature Flag: Web Application Firewall Protection
# When disabled: No WAF protection (relies on S3/CloudFront native security)
# When enabled: OWASP Top 10 protection, rate limiting, geo-blocking
# Dependencies: Requires enable_cloudfront = true (AWS architectural constraint)
# Cost Impact: ~$5-10/month additional when enabled
variable "enable_waf" {
  description = "Enable WAF Web ACL for CloudFront distribution (requires enable_cloudfront = true)"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5-minute period from single IP"
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 20000000
    error_message = "WAF rate limit must be between 100 and 20,000,000."
  }
}

variable "enable_geo_blocking" {
  description = "Enable WAF geographic blocking"
  type        = bool
  default     = false
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = []
}

variable "ip_whitelist" {
  description = "List of IP addresses/CIDR blocks to whitelist"
  type        = list(string)
  default     = []
}

variable "ip_blacklist" {
  description = "List of IP addresses/CIDR blocks to blacklist"
  type        = list(string)
  default     = []
}

variable "max_request_body_size" {
  description = "Maximum request body size in bytes"
  type        = number
  default     = 8192

  validation {
    condition     = var.max_request_body_size >= 1 && var.max_request_body_size <= 8192
    error_message = "Maximum request body size must be between 1 and 8192 bytes."
  }
}

# IAM Configuration
variable "create_github_oidc_provider" {
  description = "Create GitHub OIDC identity provider (false if already exists)"
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session duration for GitHub Actions role (seconds)"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Max session duration must be between 3600 (1 hour) and 43200 (12 hours) seconds."
  }
}

variable "enable_readonly_access" {
  description = "Enable ReadOnlyAccess policy for GitHub Actions role"
  type        = bool
  default     = false
}


variable "create_deployment_service_role" {
  description = "Create additional service role for automated deployments"
  type        = bool
  default     = false
}

# Monitoring Configuration
variable "alert_email_addresses" {
  description = "List of email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "cloudfront_error_rate_threshold" {
  description = "CloudFront 4xx error rate threshold (percentage)"
  type        = number
  default     = 5.0

  validation {
    condition     = var.cloudfront_error_rate_threshold >= 0 && var.cloudfront_error_rate_threshold <= 100
    error_message = "CloudFront error rate threshold must be between 0 and 100."
  }
}

variable "cache_hit_rate_threshold" {
  description = "Minimum acceptable cache hit rate (percentage)"
  type        = number
  default     = 85.0

  validation {
    condition     = var.cache_hit_rate_threshold >= 0 && var.cache_hit_rate_threshold <= 100
    error_message = "Cache hit rate threshold must be between 0 and 100."
  }
}

variable "waf_blocked_requests_threshold" {
  description = "WAF blocked requests threshold for alerts"
  type        = number
  default     = 100
}

variable "s3_billing_threshold" {
  description = "S3 billing threshold in USD"
  type        = number
  default     = 10.0
}

variable "cloudfront_billing_threshold" {
  description = "CloudFront billing threshold in USD"
  type        = number
  default     = 20.0
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "50"
}

variable "enable_deployment_metrics" {
  description = "Enable custom deployment success/failure metrics"
  type        = bool
  default     = true
}

variable "enable_budget" {
  description = "Enable AWS Budget for cost tracking (disable temporarily if orphaned)"
  type        = bool
  default     = true
}

# Security Configuration
variable "create_kms_key" {
  description = "Create KMS key for encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "Existing KMS key ID for encryption (optional)"
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN for encryption (optional)"
  type        = string
  default     = null
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

# Route 53 Configuration
variable "create_route53_zone" {
  description = "Create Route 53 hosted zone"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Primary domain name for Route 53 zone"
  type        = string
  default     = null
}

# Common Tags
variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "static-website"
    Environment = "production"
    ManagedBy   = "opentofu"
    Owner       = "DevOps"
    CostCenter  = "Engineering"
  }
}

# Feature Flags
variable "enable_enhanced_security" {
  description = "Enable enhanced security features"
  type        = bool
  default     = true
}

variable "enable_performance_optimization" {
  description = "Enable performance optimization features"
  type        = bool
  default     = true
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

# AWS Managed Policy IDs (12-factor app configuration)
variable "managed_caching_disabled_policy_id" {
  description = "AWS managed CachingDisabled policy ID"
  type        = string
  default     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

variable "managed_cors_s3_origin_policy_id" {
  description = "AWS managed CORS-S3Origin policy ID"
  type        = string
  default     = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
}

