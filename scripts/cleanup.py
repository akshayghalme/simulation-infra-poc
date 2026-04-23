#!/usr/bin/env python3
"""
Cost Guard — Automated cleanup for simulation EC2 instances.

Scans for running instances tagged 'Project: Simulation' and stops any
that have been running longer than the configured threshold (default: 4 hours).

Usage:
    python cleanup.py              # Stop instances exceeding threshold
    python cleanup.py --dry-run    # Report only, no action taken
    python cleanup.py --hours 2    # Custom threshold (2 hours)

Designed to run as:
    - A cron job on a management instance
    - An AWS EventBridge → Lambda trigger
    - A GitHub Actions scheduled workflow
"""

import argparse
import sys
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_REGION = "ap-south-1"
DEFAULT_MAX_HOURS = 4
TAG_KEY = "Project"
TAG_VALUE = "Simulation"


def get_simulation_instances(ec2_client: boto3.client) -> list[dict]:
    """Find all running EC2 instances tagged with Project=Simulation."""
    filters = [
        {"Name": "tag:{}".format(TAG_KEY), "Values": [TAG_VALUE]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ]

    try:
        response = ec2_client.describe_instances(Filters=filters)
    except ClientError as e:
        print(f"[ERROR] Failed to describe instances: {e}")
        sys.exit(1)

    instances = []
    for reservation in response.get("Reservations", []):
        for instance in reservation.get("Instances", []):
            # Extract the Name tag for readable logging
            name = "unnamed"
            for tag in instance.get("Tags", []):
                if tag["Key"] == "Name":
                    name = tag["Value"]
                    break

            instances.append({
                "id": instance["InstanceId"],
                "name": name,
                "type": instance["InstanceType"],
                "launch_time": instance["LaunchTime"],
                "state": instance["State"]["Name"],
            })

    return instances


def calculate_runtime_hours(launch_time: datetime) -> float:
    """Calculate how many hours an instance has been running."""
    now = datetime.now(timezone.utc)
    delta = now - launch_time
    return delta.total_seconds() / 3600


def stop_instances(ec2_client: boto3.client, instance_ids: list[str]) -> None:
    """Stop the given EC2 instances."""
    try:
        ec2_client.stop_instances(InstanceIds=instance_ids)
        print(f"[ACTION] Stop request sent for: {', '.join(instance_ids)}")
    except ClientError as e:
        print(f"[ERROR] Failed to stop instances: {e}")
        sys.exit(1)


def run_cost_guard(region: str, max_hours: float, dry_run: bool) -> None:
    """Main cost guard logic."""
    ec2_client = boto3.client("ec2", region_name=region)

    print("=" * 60)
    print("  COST GUARD — Simulation Instance Cleanup")
    print("=" * 60)
    print(f"  Region:       {region}")
    print(f"  Tag Filter:   {TAG_KEY}={TAG_VALUE}")
    print(f"  Threshold:    {max_hours} hours")
    print(f"  Mode:         {'DRY RUN' if dry_run else 'LIVE'}")
    print("=" * 60)
    print()

    instances = get_simulation_instances(ec2_client)

    if not instances:
        print("[OK] No running simulation instances found. Nothing to do.")
        return

    print(f"[INFO] Found {len(instances)} running simulation instance(s):\n")

    to_stop = []
    for inst in instances:
        runtime = calculate_runtime_hours(inst["launch_time"])
        status = "EXCEEDS THRESHOLD" if runtime > max_hours else "within limit"

        print(
            f"  {inst['id']}  {inst['name']:<30}  "
            f"{inst['type']:<12}  {runtime:>6.1f}h  [{status}]"
        )

        if runtime > max_hours:
            to_stop.append(inst["id"])

    print()

    if not to_stop:
        print(f"[OK] All instances are within the {max_hours}-hour limit.")
        return

    print(f"[WARN] {len(to_stop)} instance(s) exceed the threshold.\n")

    if dry_run:
        print("[DRY RUN] The following instances WOULD be stopped:")
        for iid in to_stop:
            print(f"  → {iid}")
        print("\n[DRY RUN] No action taken. Remove --dry-run to enforce.")
    else:
        stop_instances(ec2_client, to_stop)
        print(f"\n[DONE] {len(to_stop)} instance(s) stopped successfully.")


def main():
    parser = argparse.ArgumentParser(
        description="Cost Guard: Stop simulation instances running beyond threshold.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--region",
        default=DEFAULT_REGION,
        help=f"AWS region (default: {DEFAULT_REGION})",
    )
    parser.add_argument(
        "--hours",
        type=float,
        default=DEFAULT_MAX_HOURS,
        help=f"Max runtime in hours before stopping (default: {DEFAULT_MAX_HOURS})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report only — do not stop any instances",
    )

    args = parser.parse_args()
    run_cost_guard(region=args.region, max_hours=args.hours, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
