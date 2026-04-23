# ---------------------------------------------------------------------------
# Remote Backend Configuration
# ---------------------------------------------------------------------------
# Production-grade state management:
#   - S3 for durable, versioned state storage
#   - DynamoDB for state locking (prevents concurrent applies)
#   - Encryption at rest enabled
#
# SETUP: Create the S3 bucket and DynamoDB table before running terraform init.
#   aws s3api create-bucket --bucket simulation-infra-tfstate-<ACCOUNT_ID> --region ap-south-1 \
#       --create-bucket-configuration LocationConstraint=ap-south-1
#   aws s3api put-bucket-versioning --bucket simulation-infra-tfstate-<ACCOUNT_ID> \
#       --versioning-configuration Status=Enabled
#   aws dynamodb create-table --table-name simulation-infra-lock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST --region ap-south-1
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "simulation-infra-tfstate"
    key            = "env/poc/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "simulation-infra-lock"
  }
}
