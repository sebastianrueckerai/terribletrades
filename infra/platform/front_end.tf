resource "null_resource" "prepare_frontend" {
  triggers = {
    # Watch for changes in source code
    src_hash    = "${md5(join("", [for f in fileset("${path.module}/../../fe/src", "**") : filemd5("${path.module}/../../fe/src/${f}")]))}"
    public_hash = "${md5(join("", [for f in fileset("${path.module}/../../fe/public", "**") : filemd5("${path.module}/../../fe/public/${f}")]))}"
    # Force rebuilding when needed
    rebuild_timestamp = "${timestamp()}"
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../../fe"
    command     = <<-EOT
      echo "Building React frontend..."
      npm install
      npm run build
      
      echo "Creating zip archive of frontend files..."
      cd dist
      zip -r ../frontend.zip *
      cd ..
      
      # Generate a checksum file
      sha256sum frontend.zip > frontend.zip.sha256
      
      echo "Frontend zip archive created: frontend.zip"
      echo "Checksum saved to: frontend.zip.sha256"
    EOT
  }
}

# Output the frontend zip path for reference
output "frontend_zip_path" {
  value       = "${path.module}/../../fe/frontend.zip"
  description = "Path to the zipped frontend files for Phase 2"
}
