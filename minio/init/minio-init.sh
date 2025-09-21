#!/bin/sh
set -e

echo "Waiting for MinIO at ${MINIO_ENDPOINT}..."
until (curl -s ${MINIO_ENDPOINT}/minio/health/ready >/dev/null 2>&1); do
  sleep 2
done
echo "MinIO ready."

mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASS}"

# Create bucket (idempotent) + versioning
mc mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}"
mc version enable "${MINIO_ALIAS}/${MINIO_BUCKET}"

# Lifecycle rule (optional)
mc ilm add --id clean-multipart --expiry-days 7 "${MINIO_ALIAS}/${MINIO_BUCKET}" || true

# App user + policy
if ! mc admin user info "${MINIO_ALIAS}" "${S3_APP_ACCESS_KEY}" >/dev/null 2>&1; then
  mc admin user add "${MINIO_ALIAS}" "${S3_APP_ACCESS_KEY}" "${S3_APP_SECRET_KEY}"
fi

# Create a policy dynamically for the configured bucket
TMP_POLICY=/tmp/ps-app-policy.json
cat > "$TMP_POLICY" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketList",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListBucketVersions"
      ],
      "Resource": ["arn:aws:s3:::${MINIO_BUCKET}"]
    },
    {
      "Sid": "ObjectRW",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": ["arn:aws:s3:::${MINIO_BUCKET}/*"]
    }
  ]
}
EOF

mc admin policy create "${MINIO_ALIAS}" ps-app-policy "$TMP_POLICY" || true
mc admin policy attach "${MINIO_ALIAS}" --user "${S3_APP_ACCESS_KEY}" --policy ps-app-policy || true

echo "MinIO bootstrap complete."
