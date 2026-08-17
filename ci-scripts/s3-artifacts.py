import argparse
import logging
import os

import boto3
import botocore.client


def connect() -> boto3.resource:
    """
    Connect to S3 using environment variables.

    Required env vars:
        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        AWS_REGION
    """
    logging.debug("Going to connect")
    s3_resource = boto3.resource(
        "s3",
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ["AWS_REGION"],
        config=botocore.config.Config(signature_version="s3v4"),
    )
    logging.debug("Connected")
    return s3_resource


def upload_file(s3_resource, local_name, bucket, remote_name):
    logging.debug(f"Going to upload {local_name}")
    s3_bucket = s3_resource.Bucket(name=bucket)
    s3_object = s3_bucket.Object(key=remote_name)
    s3_object.upload_file(Filename=local_name, ExtraArgs={"ServerSideEncryption": "AES256"})
    size = s3_object.content_length
    logging.info(f"Uploaded {size}B of {local_name} as {remote_name}")
    return size


def get_presigned_url(s3_resource, bucket, remote_name):
    logging.debug(f"Going to generate signed URL for {remote_name}")
    download_url = s3_resource.meta.client.generate_presigned_url(
        ClientMethod="get_object",
        Params={
            "Bucket": bucket,
            "Key": remote_name,
        },
        ExpiresIn=3600 * 3,
    )
    logging.info(f"For {remote_name} obtained signed url {download_url}")
    return download_url


def delete_files(
    s3_resource: boto3.resource, bucket_name: str, file_paths: str | list[str]
) -> dict | bool:
    """
    Delete s3-objects from s3 bucket
    Args:
        s3_resource: create s3 resource object from using connect() and pass
        bucket_name: s3 bucket name
        file_paths: filename or list of file names you want to delete
    Returns:
        Delete response or False
    """
    # Create a list of objects to delete
    if isinstance(file_paths, list):
        objects_to_delete = [{"Key": path} for path in file_paths]
    elif isinstance(file_paths, str):
        objects_to_delete = [{"Key": file_paths}]
    else:
        print(f"file_paths attribute must be string or list not {type(file_paths)}")
        return False
    logging.debug("Going to delete")
    if objects_to_delete:
        response = s3_resource.meta.client.delete_objects(
            Bucket=bucket_name, Delete={"Objects": objects_to_delete}
        )
        logging.debug("object/objects deleted")
        return response


def list_objects(s3_resource, bucket_name: str, prefix: str = "") -> list[str]:
    """
    List object keys in an S3 bucket.
    Args:
        s3_resource: S3 resource object from connect()
        bucket_name: S3 bucket name
        prefix: optional prefix to filter objects
    Returns:
        List of object keys
    """
    logging.debug(f"Going to list objects in {bucket_name} with prefix '{prefix}'")
    s3_bucket = s3_resource.Bucket(name=bucket_name)
    keys = [obj.key for obj in s3_bucket.objects.filter(Prefix=prefix)]
    logging.info(f"Found {len(keys)} objects in {bucket_name}")
    return keys


def download_file(s3_resource, bucket_name: str, remote_name: str, local_name: str):
    """
    Download a file from S3.
    Args:
        s3_resource: S3 resource object from connect()
        bucket_name: S3 bucket name
        remote_name: key of the object in S3
        local_name: local path to save the file to
    """
    logging.debug(f"Going to download {remote_name}")
    s3_bucket = s3_resource.Bucket(name=bucket_name)
    s3_object = s3_bucket.Object(key=remote_name)
    s3_object.download_file(Filename=local_name)
    logging.info(f"Downloaded {remote_name} to {local_name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="S3 artifact collector POC")
    parser.add_argument(
        "action",
        choices=["push", "list", "download", "delete"],
        help="Action to perform",
    )
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument("--local", help="Local file path (for push/download)")
    parser.add_argument("--remote", help="Remote S3 key (for push/download/delete)")
    parser.add_argument("--prefix", default="", help="Prefix filter (for list)")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    s3 = connect()

    if args.action == "push":
        if not args.local or not args.remote:
            parser.error("push requires --local and --remote")
        upload_file(s3, args.local, args.bucket, args.remote)

    elif args.action == "list":
        keys = list_objects(s3, args.bucket, args.prefix)
        for key in keys:
            print(key)

    elif args.action == "download":
        if not args.remote or not args.local:
            parser.error("download requires --remote and --local")
        download_file(s3, args.bucket, args.remote, args.local)

    elif args.action == "delete":
        if not args.remote:
            parser.error("delete requires --remote")
        delete_files(s3, args.bucket, args.remote)
