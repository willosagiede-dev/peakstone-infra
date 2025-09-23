#!/bin/sh
set -e

echo "Waiting for MinIO at ${MINIO_ENDPOINT} (alias set loop)..."
until mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASS}" >/dev/null 2>&1; do
  sleep 2
done
echo "MinIO alias set."

# Create bucket (idempotent) + versioning
mc mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}"
mc version enable "${MINIO_ALIAS}/${MINIO_BUCKET}"

# Lifecycle rule (optional): expire incomplete uploads/old objects after 7 days
mc ilm add "${MINIO_ALIAS}/${MINIO_BUCKET}" --expire-days 7 || true

# App user + policy
if ! mc admin user info "${MINIO_ALIAS}" "${S3_APP_ACCESS_KEY}" >/dev/null 2>&1; then
  mc admin user add "${MINIO_ALIAS}" "${S3_APP_ACCESS_KEY}" "${S3_APP_SECRET_KEY}"
fi

# Create a policy dynamically for the configured bucket
TMP_POLICY=/tmp/app-policy.json
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

mc admin policy create "${MINIO_ALIAS}" app-policy "$TMP_POLICY" || true
# Attach policy to user (syntax without --policy per newer mc versions)
mc admin policy attach "${MINIO_ALIAS}" --user "${S3_APP_ACCESS_KEY}" app-policy || true

# --- Loki bucket bootstrap (idempotent) ---
# Create separate bucket for Loki log storage
if ! mc ls "${MINIO_ALIAS}/loki" >/dev/null 2>&1; then
  echo "Creating Loki bucket..."
  mc mb --ignore-existing "${MINIO_ALIAS}/loki"
  # Versioning optional for Loki; enable if desired
  mc version enable "${MINIO_ALIAS}/loki" || true
  # Basic lifecycle: expire incomplete uploads / old parts (optional)
  mc ilm add "${MINIO_ALIAS}/loki" --expire-days 7 || true
fi

# Loki user + policy (least-privilege for bucket 'loki')
if [ -n "${LOKI_ACCESS_KEY}" ] && [ -n "${LOKI_SECRET_KEY}" ]; then
  if ! mc admin user info "${MINIO_ALIAS}" "${LOKI_ACCESS_KEY}" >/dev/null 2>&1; then
    mc admin user add "${MINIO_ALIAS}" "${LOKI_ACCESS_KEY}" "${LOKI_SECRET_KEY}"
  fi
  LOKI_POLICY=/tmp/loki-policy.json
  cat > "$LOKI_POLICY" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LokiBucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:ListBucketVersions"],
      "Resource": ["arn:aws:s3:::loki"]
    },
    {
      "Sid": "LokiObjectRW",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": ["arn:aws:s3:::loki/*"]
    }
  ]
}
EOF
  mc admin policy create "${MINIO_ALIAS}" loki-policy "$LOKI_POLICY" || true
  mc admin policy attach "${MINIO_ALIAS}" --user "${LOKI_ACCESS_KEY}" loki-policy || true
fi

echo "MinIO bootstrap complete."
