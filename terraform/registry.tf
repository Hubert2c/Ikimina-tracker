# ============================================ PRIVATE CONTAINER REGISTRY ====
# Amazon ECR. The CD pipeline pushes each image here (tagged with the Git
# commit SHA, plus "latest"), and the app VM pulls it with a short-lived
# token the pipeline hands it. Images are scanned on push.
resource "aws_ecr_repository" "app" {
  # checkov:skip=CKV_AWS_51:Tags must be mutable because the pipeline also moves the "latest" tag; deploys always use the immutable commit-SHA tag.
  # checkov:skip=CKV_AWS_136:AES-256 encryption (AWS managed) is used; a customer-managed KMS key adds cost without benefit here.
  name                 = var.image_repository
  image_tag_mutability = "MUTABLE"
  force_delete         = true # let `terraform destroy` remove it even with images inside

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep only the 10 most recent images, so storage stays inside the free tier.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
