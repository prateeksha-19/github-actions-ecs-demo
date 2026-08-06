# Persistent storage for /data (database, audio, transcription results). This is
# what keeps the project's "avoid data loss at all costs" invariant true across
# Fargate task restarts and redeploys — Fargate ephemeral storage is wiped every
# time a task is replaced.
#
# Only /data is persisted. /models (re-downloadable) and /runtime (dependency
# bootstrap venv) stay on ephemeral storage: putting the venv on NFS would make
# every import painfully slow.

resource "aws_efs_file_system" "data" {
  count = var.enable_efs ? 1 : 0

  creation_token = "${local.name}-data"
  encrypted      = true

  tags = { Name = "${local.name}-data" }
}

resource "aws_efs_mount_target" "data" {
  count = var.enable_efs ? length(aws_subnet.public) : 0

  file_system_id  = aws_efs_file_system.data[0].id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs[0].id]
}

# Access point pins ownership to appuser (UID/GID 10000, matching the Dockerfile)
# and roots the mount at /data so the container sees a clean, correctly-owned dir.
resource "aws_efs_access_point" "data" {
  count = var.enable_efs ? 1 : 0

  file_system_id = aws_efs_file_system.data[0].id

  posix_user {
    uid = 10000
    gid = 10000
  }

  root_directory {
    path = "/data"
    creation_info {
      owner_uid   = 10000
      owner_gid   = 10000
      permissions = "0755"
    }
  }

  tags = { Name = "${local.name}-data-ap" }
}
