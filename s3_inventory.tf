# S3 INVENTORY (CSV to be changed to Parset for Athena)

locals {
  source_bucket_name  = "${var.project}-${var.TF_stage}-data"
  reports_bucket_name = "${var.project}-${var.TF_stage}-inventory-reports"
}

# Get current AWS Account ID for bucket policy conditions (aws:SourceAccount)
data "aws_caller_identity" "current" {}

# Existing source bucket (already created on s3.ft)
data "aws_s3_bucket" "inventory_target" {
  bucket = local.source_bucket_name
}

# Reports bucket (created in s3.tf via module)
data "aws_s3_bucket" "inventory_reports" {
  bucket = local.reports_bucket_name
}

# Read existing reports bucket policy (e.g., SecureTransport deny)
data "aws_s3_bucket_policy" "inventory_reports_existing" {
  bucket = data.aws_s3_bucket.inventory_reports.id
}

# Add required permissions for S3 Inventory
data "aws_iam_policy_document" "inventory_reports_additions" {

statement {
  sid    = "AllowS3InventoryWrite"
  effect = "Allow"

  principals {
    type        = "Service"
    identifiers = ["s3.amazonaws.com"]
  }

  actions = ["s3:PutObject"]

  resources = [
    "arn:aws:s3:::${local.reports_bucket_name}/s3-inventory/*"
  ]

  # Ensure the request comes from this AWS account
  condition {
    test     = "StringEquals"
    variable = "aws:SourceAccount"
    values   = [data.aws_caller_identity.current.account_id]
  }

  # Ensure the request comes from the inventoried source bucket
  condition {
    test     = "ArnLike"
    variable = "aws:SourceArn"
    values   = [data.aws_s3_bucket.inventory_target.arn]
  }
}

statement {
  sid    = "AllowS3InventoryDestinationValidation"
  effect = "Allow"

  principals {
    type        = "Service"
    identifiers = ["s3.amazonaws.com"]
  }

  actions = [
    "s3:GetBucketAcl",
    "s3:ListBucket"
  ]

  resources = [
    "arn:aws:s3:::${local.reports_bucket_name}"
  ]

  # Ensure the request comes from this AWS account
  condition {
    test     = "StringEquals"
    variable = "aws:SourceAccount"
    values   = [data.aws_caller_identity.current.account_id]
  }

  # Ensure the request comes from the inventoried source bucket
  condition {
    test     = "ArnLike"
    variable = "aws:SourceArn"
    values   = [data.aws_s3_bucket.inventory_target.arn]
  }
}
# Merge existing policy with new statements
data "aws_iam_policy_document" "inventory_reports_merged" {
  source_policy_documents = [
    data.aws_s3_bucket_policy.inventory_reports_existing.policy
  ]

  override_policy_documents = [
    data.aws_iam_policy_document.inventory_reports_additions.json
  ]
}

resource "aws_s3_bucket_policy" "inventory_reports" {
  bucket = data.aws_s3_bucket.inventory_reports.id
  policy = data.aws_iam_policy_document.inventory_reports_merged.json
}

# Enable daily S3 Inventory (CSV)
resource "aws_s3_bucket_inventory" "daily_inventory" {
  bucket = data.aws_s3_bucket.inventory_target.id
  name   = "daily-inventory"

  included_object_versions = "Current"

  schedule {
    frequency = "Daily"
  }

  filter {
    prefix = ""
  }

  destination {
    bucket {
      bucket_arn = data.aws_s3_bucket.inventory_reports.arn
      format     = "CSV"
      prefix     = "s3-inventory"

      bucket_owner_full_control = true
    }
  }

  depends_on = [aws_s3_bucket_policy.inventory_reports]
}
