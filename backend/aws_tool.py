from typing import List, Any
import time

try:
    from strands import tool
except ImportError:
    from mock_strands import tool

# Global session reference
_account_session = None
_region = "ap-southeast-2"


def set_session(session, region="ap-southeast-2"):
    """Set the AWS session for tools to use"""
    global _account_session, _region
    _account_session = session
    _region = region


@tool
def use_aws(
    service_name: str,
    operation_name: str,
    parameters: dict = None,
    region: str = None
) -> dict:
    """REQUIRED TOOL: You MUST use this tool for ALL AWS resource queries. This is the ONLY way to retrieve live AWS data.

    MANDATORY USAGE:
    - For S3 queries: use_aws(service_name="s3", operation_name="list_buckets")
    - For EC2 queries: use_aws(service_name="ec2", operation_name="describe_instances")
    - For VPC queries: use_aws(service_name="ec2", operation_name="describe_vpcs")
    - For IAM queries: use_aws(service_name="iam", operation_name="list_users")

    Args:
        service_name: AWS service (ec2, s3, cloudformation, iam, lambda, rds)
        operation_name: API operation (describe_instances, list_buckets, etc.)
        parameters: Optional API parameters as dict
        region: AWS region (default: ap-southeast-2)

    Verifications:
        In case of any ambiguous inputs entered by the user, ask the user to verify
        the query and also provide some suggestions.

        For example, if the user asks "list my clusters", ask the user to clarify
        if you are asking about RDS clusters or ECS clusters or EKS clusters etc.

    Returns:
        Dictionary with resource details
    """
    if parameters is None:
        parameters = {}
    if region is None:
        region = _region

    if _account_session is None:
        return {"error": "Session not initialized"}

    try:
        client = _account_session.client(service_name, region_name=region)
        operation = getattr(client, operation_name)
        result = operation(**parameters)

        if isinstance(result, dict):
            result.pop('ResponseMetadata', None)

        return result

    except Exception as e:
        return {
            "success": False,
            "error": str(e)[:200]
        }


class AWSToolManager:
    """Manages native AWS tools with session credentials"""

    def __init__(self, account_session, account_id: str, region: str = "ap-southeast-2"):
        self.account_session = account_session
        self.account_id = account_id
        self.region = region

        print(f"DEBUG: Using account session for AWS tools - Account ID: {account_id}")

        try:
            sts_client = account_session.client('sts')
            identity = sts_client.get_caller_identity()
            print(f"DEBUG: AWSToolManager session identity: {identity.get('Arn', 'Unknown')}")
        except Exception as e:
            print(f"DEBUG: Could not verify AWSToolManager session identity: {e}")

        set_session(self.account_session, self.region)

    def load_tools_for_query(self, query: str) -> List[Any]:
        """Load native AWS tools based on query content"""
        return [use_aws]
