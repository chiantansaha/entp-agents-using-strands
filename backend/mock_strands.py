"""Mock Strands implementation for development without build issues."""
import json
import re
from datetime import datetime
from typing import Any, Dict, List, Callable, Optional, AsyncGenerator

# Mock tool decorator
def tool(func: Callable) -> Callable:
    """Mock tool decorator that preserves function metadata."""
    func._is_tool = True
    return func


def _mask_account_numbers(text: str) -> str:
    """Mask 12-digit AWS account numbers with xxxxxxxxxxxx."""
    return re.sub(r'\b\d{12}\b', 'xxxxxxxxxxxx', text)


# ---------------------------------------------------------------------------
# HTML formatting helpers
# ---------------------------------------------------------------------------

def _fmt_date(val) -> str:
    if val is None:
        return "N/A"
    if isinstance(val, datetime):
        return val.strftime("%b %d, %Y")
    return str(val)[:10]

def _tag(tag, content, **attrs):
    attr_str = "".join(f' {k.replace("_","-")}="{v}"' for k, v in attrs.items())
    return f"<{tag}{attr_str}>{content}</{tag}>"

def _table(headers: list, rows: list) -> str:
    th = "".join(_tag("th", h, style="padding:8px 12px;background:#4a4a4a;color:#fff;text-align:left;white-space:nowrap") for h in headers)
    thead = _tag("tr", th)
    tbody_rows = []
    for i, row in enumerate(rows):
        bg = "#f5f5f5" if i % 2 == 0 else "#ebebeb"
        td = "".join(_tag("td", str(c) if c is not None else "N/A", style="padding:7px 12px;color:#222;border-bottom:1px solid #d0d0d0") for c in row)
        tbody_rows.append(_tag("tr", td, style=f"background:{bg}"))
    table_inner = _tag("thead", thead) + _tag("tbody", "".join(tbody_rows))
    return _tag("table", table_inner, style="border-collapse:collapse;width:100%;font-family:monospace;font-size:13px;margin:12px 0")

def _header(emoji_title: str) -> str:
    return _tag("h3", emoji_title, style="color:#4fc3f7;margin:16px 0 8px 0;font-family:sans-serif")

def _summary(text: str) -> str:
    return _tag("p", text, style="color:#444;font-family:sans-serif;margin:6px 0")

def _tip(text: str) -> str:
    return _tag("p", f"💡 {text}", style="color:#2e7d32;font-family:sans-serif;font-style:italic;margin:6px 0")


def format_s3_response(data: dict, region: str) -> str:
    region_label = region.upper()
    buckets = data.get("Buckets", [])
    html = _header(f"🪣 S3 BUCKETS IN {region_label} 🪣")
    if not buckets:
        return html + _summary("No S3 buckets found.")
    rows = [[b.get("Name", "N/A"), _fmt_date(b.get("CreationDate"))] for b in buckets]
    html += _table(["Bucket Name", "Creation Date"], rows)
    html += _summary(f"Total: {len(buckets)} bucket(s) found.")
    html += _tip("S3 buckets are globally unique but created in a specific region.")
    return html


def format_ec2_response(data: dict, region: str) -> str:
    region_label = region.upper()
    reservations = data.get("Reservations", [])
    instances = [i for r in reservations for i in r.get("Instances", [])]
    html = _header(f"🖥️ EC2 INSTANCES IN {region_label} 🖥️")
    if not instances:
        return html + _summary("No EC2 instances found.")
    rows = []
    for i in instances:
        name = next((t["Value"] for t in i.get("Tags", []) if t["Key"] == "Name"), "—")
        rows.append([
            i.get("InstanceId", "N/A"),
            i.get("InstanceType", "N/A"),
            i.get("State", {}).get("Name", "N/A"),
            name,
            _fmt_date(i.get("LaunchTime"))
        ])
    html += _table(["Instance ID", "Type", "State", "Name", "Launch Date"], rows)
    running = sum(1 for r in rows if r[2] == "running")
    html += _summary(f"Total: {len(instances)} instance(s) — {running} running.")
    html += _tip("Use EC2 Instance Connect or SSM Session Manager for secure access.")
    return html


def format_lambda_response(data: dict, region: str) -> str:
    region_label = region.upper()
    functions = data.get("Functions", [])
    html = _header(f"⚡ LAMBDA FUNCTIONS IN {region_label} ⚡")
    if not functions:
        return html + _summary("No Lambda functions found.")
    rows = [[
        f.get("FunctionName", "N/A"),
        f.get("Runtime", "N/A"),
        f.get("Handler", "N/A"),
        f"{round(f.get('CodeSize', 0) / 1024, 1)} KB",
        _fmt_date(f.get("LastModified"))
    ] for f in functions]
    html += _table(["Function Name", "Runtime", "Handler", "Code Size", "Last Modified"], rows)
    html += _summary(f"Total: {len(functions)} function(s) found.")
    html += _tip("Monitor Lambda with CloudWatch Logs for invocation errors and duration.")
    return html


def format_rds_response(data: dict, region: str) -> str:
    region_label = region.upper()
    instances = data.get("DBInstances", [])
    html = _header(f"🗄️ RDS INSTANCES IN {region_label} 🗄️")
    if not instances:
        return html + _summary("No RDS instances found.")
    rows = [[
        i.get("DBInstanceIdentifier", "N/A"),
        i.get("DBInstanceClass", "N/A"),
        i.get("Engine", "N/A"),
        i.get("DBInstanceStatus", "N/A"),
        i.get("MultiAZ", False) and "Yes" or "No"
    ] for i in instances]
    html += _table(["DB Identifier", "Class", "Engine", "Status", "Multi-AZ"], rows)
    html += _summary(f"Total: {len(instances)} DB instance(s) found.")
    html += _tip("Enable automated backups and Multi-AZ for production workloads.")
    return html


def format_iam_users_response(data: dict) -> str:
    users = data.get("Users", [])
    html = _header("👥 IAM USERS (GLOBAL) 👥")
    if not users:
        return html + _summary("No IAM users found.")
    rows = [[
        u.get("UserName", "N/A"),
        u.get("UserId", "N/A"),
        _fmt_date(u.get("CreateDate")),
        _fmt_date(u.get("PasswordLastUsed"))
    ] for u in users]
    html += _table(["Username", "User ID", "Created", "Last Login"], rows)
    html += _summary(f"Total: {len(users)} IAM user(s).")
    html += _tip("Apply least-privilege policies and enable MFA for all IAM users.")
    return html


def format_iam_roles_response(data: dict) -> str:
    roles = data.get("Roles", [])
    html = _header("🎭 IAM ROLES (GLOBAL) 🎭")
    if not roles:
        return html + _summary("No IAM roles found.")
    rows = [[
        r.get("RoleName", "N/A"),
        r.get("RoleId", "N/A"),
        _fmt_date(r.get("CreateDate")),
        r.get("Description", "—")[:60]
    ] for r in roles]
    html += _table(["Role Name", "Role ID", "Created", "Description"], rows)
    html += _summary(f"Total: {len(roles)} IAM role(s).")
    html += _tip("Review role trust policies regularly to ensure least-privilege access.")
    return html


def format_kms_response(data: dict, region: str) -> str:
    region_label = region.upper()
    keys = data.get("Keys", [])
    html = _header(f"🔑 KMS KEYS IN {region_label} 🔑")
    if not keys:
        return html + _summary("No KMS keys found.")
    rows = [[k.get("KeyId", "N/A"), k.get("KeyArn", "N/A")] for k in keys]
    html += _table(["Key ID", "Key ARN"], rows)
    html += _summary(f"Total: {len(keys)} KMS key(s).")
    html += _tip("Rotate KMS keys annually and restrict key policies to required principals only.")
    return html


def format_cloudformation_response(data: dict, region: str) -> str:
    region_label = region.upper()
    stacks = data.get("Stacks", [])
    html = _header(f"☁️ CLOUDFORMATION STACKS IN {region_label} ☁️")
    if not stacks:
        return html + _summary("No CloudFormation stacks found.")
    rows = [[
        s.get("StackName", "N/A"),
        s.get("StackStatus", "N/A"),
        _fmt_date(s.get("CreationTime")),
        s.get("Description", "—")[:60]
    ] for s in stacks]
    html += _table(["Stack Name", "Status", "Created", "Description"], rows)
    html += _summary(f"Total: {len(stacks)} stack(s).")
    html += _tip("Use stack drift detection to identify manual changes to your resources.")
    return html


def format_ssm_response(data: dict, region: str) -> str:
    region_label = region.upper()
    params = data.get("Parameters", [])
    html = _header(f"⚙️ SSM PARAMETERS IN {region_label} ⚙️")
    if not params:
        return html + _summary("No SSM parameters found.")
    rows = [[
        p.get("Name", "N/A"),
        p.get("Type", "N/A"),
        _fmt_date(p.get("LastModifiedDate")),
        p.get("Description", "—")[:60]
    ] for p in params]
    html += _table(["Name", "Type", "Last Modified", "Description"], rows)
    html += _summary(f"Total: {len(params)} parameter(s).")
    html += _tip("Use SecureString type for sensitive values like passwords and API keys.")
    return html


def format_vpc_response(data: dict, region: str) -> str:
    region_label = region.upper()
    vpcs = data.get("Vpcs", [])
    html = _header(f"🌐 VPCs IN {region_label} 🌐")
    if not vpcs:
        return html + _summary("No VPCs found.")
    rows = [[
        v.get("VpcId", "N/A"),
        v.get("CidrBlock", "N/A"),
        v.get("State", "N/A"),
        "Yes" if v.get("IsDefault") else "No"
    ] for v in vpcs]
    html += _table(["VPC ID", "CIDR Block", "State", "Default"], rows)
    html += _summary(f"Total: {len(vpcs)} VPC(s).")
    html += _tip("Avoid using the default VPC for production workloads.")
    return html


def format_generic_response(data: dict, label: str) -> str:
    html = _header(f"☁️ {label.upper()} ☁️")
    html += _tag("pre", json.dumps(data, indent=2, default=str),
                 style="background:#f5f5f5;color:#222;padding:12px;border-radius:6px;overflow:auto;font-size:12px")
    return html

class MockBedrockModel:
    """Mock Bedrock model for development."""
    def __init__(self, **kwargs):
        self.model_id = kwargs.get('model_id', 'mock-model')
        self.region_name = kwargs.get('region_name', 'ap-southeast-2')
        self.temperature = kwargs.get('temperature', 0.3)
        self.top_p = kwargs.get('top_p', 0.8)
        self.streaming = kwargs.get('streaming', True)

class MockAgent:
    """Mock Agent that simulates Strands behavior with real AWS tool data."""
    
    def __init__(self, model=None, system_prompt="", tools=None, **kwargs):
        self.model = model
        self.system_prompt = system_prompt
        self.tools = tools or []
        
    def __call__(self, query: str) -> str:
        """Process query and return response from tools."""
        return self._process_query(query)
    
    async def stream_async(self, query: str) -> AsyncGenerator[Dict[str, str], None]:
        """Stream response chunks."""
        response = self._process_query(query)
        # Simulate streaming by yielding chunks
        words = response.split()
        chunk_size = 5
        for i in range(0, len(words), chunk_size):
            chunk = " ".join(words[i:i+chunk_size]) + " "
            yield {"data": chunk}
    
    def _process_query(self, query: str) -> str:
        """Process query using available tools and return actual AWS data."""
        query_lower = query.lower()

        if not self.tools:
            return "No tools available to process your query."

        # Check if we have the generic use_aws tool
        use_aws_tool = None
        for tool_func in self.tools:
            if getattr(tool_func, '__name__', '') == 'use_aws':
                use_aws_tool = tool_func
                break

        if use_aws_tool:
            return self._process_with_use_aws(query_lower, use_aws_tool)

        # Legacy: named individual tools
        return self._process_with_legacy_tools(query_lower)

    def _process_with_use_aws(self, query_lower: str, use_aws_tool) -> str:
        """Route query to use_aws tool with appropriate service/operation."""
        # (keywords, service, operation, params, formatter_fn)
        routing = [
            (('s3', 'bucket', 'storage'),
             's3', 'list_buckets', {},
             lambda d, r: format_s3_response(d, r)),
            (('ec2', 'instance', 'server', 'vm'),
             'ec2', 'describe_instances', {},
             lambda d, r: format_ec2_response(d, r)),
            (('lambda', 'function'),
             'lambda', 'list_functions', {},
             lambda d, r: format_lambda_response(d, r)),
            (('rds', 'database'),
             'rds', 'describe_db_instances', {},
             lambda d, r: format_rds_response(d, r)),
            (('iam user',),
             'iam', 'list_users', {},
             lambda d, r: format_iam_users_response(d)),
            (('iam role',),
             'iam', 'list_roles', {},
             lambda d, r: format_iam_roles_response(d)),
            (('iam',),
             'iam', 'list_users', {},
             lambda d, r: format_iam_users_response(d)),
            (('kms', 'encryption key'),
             'kms', 'list_keys', {},
             lambda d, r: format_kms_response(d, r)),
            (('cloudformation', 'stack'),
             'cloudformation', 'describe_stacks', {},
             lambda d, r: format_cloudformation_response(d, r)),
            (('ssm', 'parameter', 'param'),
             'ssm', 'describe_parameters', {},
             lambda d, r: format_ssm_response(d, r)),
            (('vpc',),
             'ec2', 'describe_vpcs', {},
             lambda d, r: format_vpc_response(d, r)),
        ]

        # Extract region hint from query
        region = "ap-southeast-2"
        if "us-east-1" in query_lower or "virginia" in query_lower:
            region = "us-east-1"
        elif "us-west-2" in query_lower or "oregon" in query_lower:
            region = "us-west-2"
        elif "eu-west-1" in query_lower or "ireland" in query_lower:
            region = "eu-west-1"

        for keywords, service, operation, params, formatter in routing:
            if any(kw in query_lower for kw in keywords):
                try:
                    result = use_aws_tool(
                        service_name=service,
                        operation_name=operation,
                        parameters=params or None,
                        region=region
                    )
                    if isinstance(result, dict) and "error" in result:
                        return f"<p style='color:#ef9a9a'>❌ Error: {result['error']}</p>"
                    return _mask_account_numbers(formatter(result, region))
                except Exception as e:
                    return f"<p style='color:#ef9a9a'>❌ Error calling {service}.{operation}: {str(e)}</p>"

        return (
            "<p style='color:#90caf9'>I'm not sure which AWS service you're asking about. "
            "Please specify a service like S3, EC2, Lambda, RDS, IAM, KMS, CloudFormation, SSM, or VPC.</p>"
        )

    def _process_with_legacy_tools(self, query_lower: str) -> str:
        """Fallback for old individually-named tool functions."""
        aws_resource_tools = {
            ('s3', 'bucket', 'storage'): 'list_s3_buckets',
            ('ec2', 'instance', 'server'): 'list_ec2_instances',
            ('lambda', 'function'): 'list_lambda_functions',
            ('rds', 'database', 'db'): 'list_rds_instances',
            ('iam', 'user'): 'list_iam_users',
            ('iam', 'role'): 'list_iam_roles',
            ('kms', 'key', 'encryption'): 'list_kms_keys',
            ('cloudformation', 'stack', 'template'): 'list_cloudformation_stacks',
            ('ssm', 'parameter', 'config'): 'list_ssm_parameters',
        }

        results = []
        for keywords, tool_name in aws_resource_tools.items():
            if any(kw in query_lower for kw in keywords):
                for tool_func in self.tools:
                    if tool_name in getattr(tool_func, '__name__', ''):
                        try:
                            results.append(_mask_account_numbers(str(tool_func())))
                        except Exception as e:
                            results.append(f"Error: {str(e)}")
                        break

        if not results:
            return (
                "Sorry, I couldn't match your query to an available tool. "
                "Try asking about S3, EC2, Lambda, RDS, IAM, KMS, CloudFormation, or SSM."
            )

        return "\n\n".join(results)


# Export the mock classes
Agent = MockAgent
BedrockModel = MockBedrockModel