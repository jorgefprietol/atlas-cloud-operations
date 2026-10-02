variable "enable_analytics" {
  type        = bool
  default     = false
  description = "Create an Athena workgroup and Glue catalog over report JSON"
}
resource "aws_s3_bucket" "analytics" {
  count  = var.enable_analytics ? 1 : 0
  bucket = "${local.prefix}-analytics-${local.account}"
}
resource "aws_s3_bucket_public_access_block" "analytics" {
  count                   = var.enable_analytics ? 1 : 0
  bucket                  = aws_s3_bucket.analytics[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics" {
  count  = var.enable_analytics ? 1 : 0
  bucket = aws_s3_bucket.analytics[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}
resource "aws_glue_catalog_database" "reports" {
  count = var.enable_analytics ? 1 : 0
  name  = replace("${local.prefix}_reports", "-", "_")
}
resource "aws_glue_catalog_table" "reports" {
  count         = var.enable_analytics ? 1 : 0
  name          = "policy_evaluations"
  database_name = aws_glue_catalog_database.reports[0].name
  table_type    = "EXTERNAL_TABLE"
  parameters    = { EXTERNAL = "TRUE", classification = "json" }
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.reports.id}/reports/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }
    dynamic "columns" {
      for_each = { operationid = "string", eventid = "string", policyversion = "string", status = "string", explanation = "string", kind = "string", region = "string", retentiondays = "int" }
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}
resource "aws_athena_workgroup" "reports" {
  count = var.enable_analytics ? 1 : 0
  name  = "${local.prefix}-reports"
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 1073741824
    result_configuration {
      output_location = "s3://${aws_s3_bucket.analytics[0].id}/results/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.main.arn
      }
    }
  }
}
