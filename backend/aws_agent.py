from collections.abc import Callable
from typing import Dict, Optional, List
import json
import os
from datetime import datetime
import time
from aws_tool import AWSToolManager, use_aws
from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.responses import StreamingResponse, PlainTextResponse
from pydantic import BaseModel
import uvicorn
import sys
try:
    from strands import Agent, tool
    from strands.models import BedrockModel
except ImportError:
    from mock_strands import Agent, tool, BedrockModel
from botocore.config import Config as BotocoreConfig
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
import re

app = FastAPI(title="AWS Resource Query API")

# Masking utility for AWS account numbers
def mask_aws_account_numbers(text: str) -> str:
    """Mask AWS account numbers (12-digit numbers) with XXXX-XXXX-XXXX."""
    if not isinstance(text, str):
        return text
    # Replace 12-digit numbers (AWS account IDs) with masked format
    return re.sub(r'\b\d{12}\b', 'XXXX-XXXX-XXXX', text)

# HTML/CSS Styling
HTML_STYLE = """
<style>
    .aws-container {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
        margin: 16px 0;
    }
    .aws-header {
        font-size: 18px;
        font-weight: 600;
        margin: 16px 0 12px 0;
        color: #262730;
        padding: 12px 0;
        border-bottom: 2px solid #d0d3d8;
    }
    .aws-table {
        width: 100%;
        border-collapse: collapse;
        margin: 12px 0;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
        border-radius: 4px;
        overflow: hidden;
        border: 1px solid #d0d3d8;
    }
    .aws-table thead {
        background-color: #f0f2f6;
        color: #262730;
    }
    .aws-table th {
        padding: 12px 16px;
        text-align: left;
        font-weight: 600;
        border: none;
        color: #262730;
        font-size: 13px;
    }
    .aws-table td {
        padding: 12px 16px;
        border-bottom: 1px solid #e6e9f0;
        color: #3c3f45;
        font-size: 13px;
    }
    .aws-table tbody tr:hover {
        background-color: #f8f9fc;
    }
    .aws-table tbody tr:last-child td {
        border-bottom: none;
    }
    .aws-summary {
        margin-top: 12px;
        padding: 12px 16px;
        background-color: #f0f2f6;
        border-left: 4px solid #808896;
        border-radius: 4px;
        font-size: 13px;
        color: #3c3f45;
        font-weight: 500;
    }
    .aws-tip {
        margin-top: 8px;
        padding: 12px 16px;
        background-color: #f0f7ff;
        border-left: 4px solid #0066cc;
        border-radius: 4px;
        font-size: 13px;
        color: #0c3975;
    }
    .status-running { color: #09a043; font-weight: 600; }
    .status-stopped { color: #d62728; font-weight: 600; }
    .status-available { color: #09a043; font-weight: 600; }
    .status-pending { color: #ff7f0e; font-weight: 600; }
    .emoji { margin-right: 6px; font-size: 14px; }
</style>
"""

# Formatting utilities
def format_s3_buckets(response: Dict) -> str:
    """Format S3 buckets response as HTML table with actual regions."""
    if 'Buckets' not in response:
        return "<div class='aws-container'><p>No S3 buckets found.</p></div>"
    
    buckets = response['Buckets']
    if not buckets:
        return "<div class='aws-container'><p>No S3 buckets found.</p></div>"
    
    # Extract bucket regions from metadata if available
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🪣</span> S3 BUCKETS (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Bucket Name</th>
                <th>Region</th>
                <th>Creation Date</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for bucket in buckets:
        name = bucket.get('Name', 'N/A')
        created = bucket.get('CreationDate', 'N/A')
        if hasattr(created, 'strftime'):
            created = created.strftime('%b %d, %Y')
        
        # Get the actual region from bucket metadata
        region = bucket.get('Region', 'us-east-1')
        
        html += f"""            <tr>
                <td>{name}</td>
                <td><span class='status-available'>🌍</span> {region}</td>
                <td>{created}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(buckets)} bucket(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Use versioning and lifecycle policies to manage storage costs
    </div>
</div>
"""
    return html

def format_ec2_instances(response: Dict) -> str:
    """Format EC2 instances response as HTML table showing actual regions."""
    instances = []
    for reservation in response.get('Reservations', []):
        instances.extend(reservation.get('Instances', []))
    
    if not instances:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>🖥️</span> EC2 INSTANCES (ALL REGIONS)</div><p>No EC2 instances found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🖥️</span> EC2 INSTANCES (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Instance ID</th>
                <th>Type</th>
                <th>Region</th>
                <th>State</th>
                <th>Name</th>
                <th>Launch Date</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for instance in instances:
        instance_id = instance.get('InstanceId', 'N/A')
        instance_type = instance.get('InstanceType', 'N/A')
        state = instance.get('State', {}).get('Name', 'N/A')
        
        # Extract region from placement AZ
        placement = instance.get('Placement', {})
        az = placement.get('AvailabilityZone', 'N/A')
        region = az[:-1] if az != 'N/A' else 'N/A'
        
        # Get name from tags
        name = 'N/A'
        for tag in instance.get('Tags', []):
            if tag.get('Key') == 'Name':
                name = tag.get('Value', 'N/A')
                break
        
        launch_time = instance.get('LaunchTime', 'N/A')
        if hasattr(launch_time, 'strftime'):
            launch_time = launch_time.strftime('%b %d, %Y')
        
        state_class = 'status-running' if state == 'running' else 'status-stopped'
        state_emoji = '🟢' if state == 'running' else '🔴'
        
        html += f"""            <tr>
                <td>{instance_id}</td>
                <td>{instance_type}</td>
                <td><span class='status-available'>🌍</span> {region}</td>
                <td><span class='{state_class}'>{state_emoji} {state}</span></td>
                <td>{name}</td>
                <td>{launch_time}</td>
            </tr>
"""
    
    running = sum(1 for i in instances if i.get('State', {}).get('Name') == 'running')
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(instances)} instance(s) ({running} running)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Consider Reserved Instances for long-running workloads to save costs
    </div>
</div>
"""
    return html

def format_lambda_functions(response: Dict) -> str:
    """Format Lambda functions response as HTML table."""
    functions = response.get('Functions', [])
    
    if not functions:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>⚡</span> LAMBDA FUNCTIONS (ALL REGIONS)</div><p>No Lambda functions found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>⚡</span> LAMBDA FUNCTIONS (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Function Name</th>
                <th>Runtime</th>
                <th>Region</th>
                <th>Memory</th>
                <th>Last Modified</th>
                <th>Timeout</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for func in functions:
        name = func.get('FunctionName', 'N/A')
        runtime = func.get('Runtime', 'N/A')
        memory = func.get('MemorySize', 'N/A')
        last_modified = func.get('LastModified', 'N/A')
        timeout = func.get('Timeout', 'N/A')
        
        if last_modified and last_modified != 'N/A':
            try:
                from datetime import datetime
                dt = datetime.fromisoformat(last_modified.replace('Z', '+00:00'))
                last_modified = dt.strftime('%b %d, %Y')
            except:
                pass
        
        # Extract region from ARN
        func_arn = func.get('FunctionArn', '')
        region = 'N/A'
        if ':' in func_arn:
            parts = func_arn.split(':')
            if len(parts) >= 4:
                region = parts[3]
        
        html += f"""            <tr>
                <td>{name}</td>
                <td>{runtime}</td>
                <td><span class='status-available'>🌍</span> {region}</td>
                <td>{memory}MB</td>
                <td>{last_modified}</td>
                <td>{timeout}s</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(functions)} function(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Monitor memory allocation and optimize code for cost savings
    </div>
</div>
"""
    return html

def format_rds_instances(response: Dict) -> str:
    """Format RDS instances response as HTML table with actual regions."""
    instances = response.get('DBInstances', [])
    
    if not instances:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>🗄️</span> RDS INSTANCES (ALL REGIONS)</div><p>No RDS instances found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🗄️</span> RDS INSTANCES (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>DB Instance</th>
                <th>Engine</th>
                <th>Region</th>
                <th>Instance Class</th>
                <th>Status</th>
                <th>Storage</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for instance in instances:
        db_id = instance.get('DBInstanceIdentifier', 'N/A')
        engine = instance.get('Engine', 'N/A')
        db_class = instance.get('DBInstanceClass', 'N/A')
        status = instance.get('DBInstanceStatus', 'N/A')
        storage = instance.get('AllocatedStorage', 'N/A')
        
        # Extract region from ARN
        db_arn = instance.get('DBInstanceArn', '')
        region = 'N/A'
        if ':' in db_arn:
            parts = db_arn.split(':')
            if len(parts) >= 4:
                region = parts[3]
        
        status_class = 'status-available' if status == 'available' else 'status-pending'
        status_emoji = '🟢' if status == 'available' else '🟡'
        
        html += f"""            <tr>
                <td>{db_id}</td>
                <td>{engine}</td>
                <td><span class='status-available'>🌍</span> {region}</td>
                <td>{db_class}</td>
                <td><span class='{status_class}'>{status_emoji} {status}</span></td>
                <td>{storage} GB</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(instances)} RDS instance(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Review unused instances and consider Multi-AZ for high availability
    </div>
</div>
"""
    return html

def format_iam_users(response: Dict) -> str:
    """Format IAM users response as HTML table."""
    users = response.get('Users', [])
    
    if not users:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>👥</span> IAM USERS (GLOBAL)</div><p>No IAM users found in your account.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>👥</span> IAM USERS (GLOBAL)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>User Name</th>
                <th>Created</th>
                <th>ARN</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for user in users:
        username = user.get('UserName', 'N/A')
        created = user.get('CreateDate', 'N/A')
        if hasattr(created, 'strftime'):
            created = created.strftime('%b %d, %Y')
        
        arn = user.get('Arn', 'N/A')
        
        html += f"""            <tr>
                <td>{username}</td>
                <td>{created}</td>
                <td>{arn}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(users)} user(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Review user permissions regularly and remove unused accounts
    </div>
</div>
"""
    return html

def format_iam_roles(response: Dict) -> str:
    """Format IAM roles response as HTML table."""
    roles = response.get('Roles', [])
    
    if not roles:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>🎭</span> IAM ROLES (GLOBAL)</div><p>No IAM roles found in your account.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🎭</span> IAM ROLES (GLOBAL)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Role Name</th>
                <th>Created</th>
                <th>ARN</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for role in roles:
        name = role.get('RoleName', 'N/A')
        created = role.get('CreateDate', 'N/A')
        if hasattr(created, 'strftime'):
            created = created.strftime('%b %d, %Y')
        
        arn = role.get('Arn', 'N/A')
        
        html += f"""            <tr>
                <td>{name}</td>
                <td>{created}</td>
                <td>{arn}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(roles)} role(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Use roles instead of access keys for better security
    </div>
</div>
"""
    return html

def format_kms_keys(response: Dict) -> str:
    """Format KMS keys response as HTML table."""
    keys = response.get('Keys', [])
    
    if not keys:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>🔐</span> KMS KEYS (ALL REGIONS)</div><p>No KMS keys found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🔐</span> KMS KEYS (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Key ID</th>
                <th>ARN</th>
                <th>Status</th>
                <th>Created</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for key in keys:
        key_id = key.get('KeyId', 'N/A')
        arn = key.get('Arn', 'N/A')
        status = "Active"  # KMS list doesn't include status, we'd need describe_key
        created = "N/A"
        
        html += f"""            <tr>
                <td>{key_id}</td>
                <td>{arn}</td>
                <td><span class='status-available'>🟢 {status}</span></td>
                <td>{created}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(keys)} KMS key(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Rotate KMS keys regularly and use key policies for fine-grained access control
    </div>
</div>
"""
    return html

def format_cloudformation_stacks(response: Dict) -> str:
    """Format CloudFormation stacks response as HTML table."""
    stacks = response.get('StackSummaries', [])
    
    if not stacks:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>🏗️</span> CLOUDFORMATION STACKS (ALL REGIONS)</div><p>No CloudFormation stacks found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>🏗️</span> CLOUDFORMATION STACKS (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Stack Name</th>
                <th>Status</th>
                <th>Created</th>
                <th>Last Updated</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for stack in stacks:
        name = stack.get('StackName', 'N/A')
        status = stack.get('StackStatus', 'N/A')
        created = stack.get('CreationTime', 'N/A')
        updated = stack.get('LastUpdatedTime', 'N/A')
        
        if hasattr(created, 'strftime'):
            created = created.strftime('%b %d, %Y')
        if hasattr(updated, 'strftime'):
            updated = updated.strftime('%b %d, %Y')
        
        status_class = 'status-available' if 'COMPLETE' in status else 'status-pending'
        status_emoji = '🟢' if 'COMPLETE' in status else '🟡'
        
        html += f"""            <tr>
                <td>{name}</td>
                <td><span class='{status_class}'>{status_emoji} {status}</span></td>
                <td>{created}</td>
                <td>{updated}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(stacks)} stack(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Use CloudFormation for infrastructure as code and version control your templates
    </div>
</div>
"""
    return html


def format_ssm_parameters(response: Dict) -> str:
    """Format SSM parameters response as HTML table."""
    parameters = response.get('Parameters', [])
    
    if not parameters:
        return "<div class='aws-container'><div class='aws-header'><span class='emoji'>⚙️</span> SSM PARAMETERS (ALL REGIONS)</div><p>No SSM parameters found.</p></div>"
    
    html = f"""{HTML_STYLE}
<div class='aws-container'>
    <div class='aws-header'><span class='emoji'>⚙️</span> SSM PARAMETERS (ALL REGIONS)</div>
    <table class='aws-table'>
        <thead>
            <tr>
                <th>Parameter Name</th>
                <th>Type</th>
                <th>Last Modified</th>
                <th>Version</th>
            </tr>
        </thead>
        <tbody>
"""
    
    for param in parameters:
        name = param.get('Name', 'N/A')
        param_type = param.get('Type', 'N/A')
        last_modified = param.get('LastModifiedDate', 'N/A')
        version = param.get('Version', 'N/A')
        
        if hasattr(last_modified, 'strftime'):
            last_modified = last_modified.strftime('%b %d, %Y')
        
        type_emoji = '🔐' if param_type == 'SecureString' else '📝'
        
        html += f"""            <tr>
                <td>{name}</td>
                <td><span class='status-available'>{type_emoji} {param_type}</span></td>
                <td>{last_modified}</td>
                <td>{version}</td>
            </tr>
"""
    
    html += f"""        </tbody>
    </table>
    <div class='aws-summary'>
        <span class='emoji'>📊</span> Found {len(parameters)} parameter(s)
    </div>
    <div class='aws-tip'>
        <span class='emoji'>💡</span> Tip: Use SecureString type for sensitive parameters and enable encryption with KMS
    </div>
</div>
"""
    return html

# Create a boto client config with custom settings
boto_config = BotocoreConfig(
    retries={"max_attempts": 3, "mode": "standard"},
    connect_timeout=5,
    read_timeout=60
)

# Configure specific Bedrock model
bedrock_model = BedrockModel(
    model_id="global.amazon.nova-2-lite-v1:0",
    region_name="ap-southeast-2",
    temperature=0.3,
    top_p=0.8,
    streaming=True,
    boto_client_config=boto_config,
)

def get_aws_system_prompt(region: str) -> str:
    """Generate AWS system prompt with dynamic region."""
    region_name = {
        "ap-southeast-2": "SYDNEY (AP-SOUTHEAST-2)",
        "us-east-1": "N. VIRGINIA (US-EAST-1)", 
        "us-west-2": "OREGON (US-WEST-2)",
        "eu-west-1": "IRELAND (EU-WEST-1)"
    }.get(region, f"{region.upper()}")
    
    return f"""You are a friendly AWS resource assistant. 

ABSOLUTE PROHIBITION - NEVER SHOW THINKING:
- NEVER use <thinking> tags or show any reasoning process
- NEVER show XML tags, processing steps, or internal monologue
- IMMEDIATELY start with emoji headers and formatted results
- NO exceptions to this rule under any circumstances

Format all responses in human-readable tables with emojis:
- ALWAYS format responses as friendly tables with emojis, NOT raw JSON
- Convert technical data into easy-to-understand summaries
- Use conversational, friendly language
- Explain what you found and provide insights

IMPORTANT: IAM is a GLOBAL service - never show region names for IAM!

Always include the region name in your headers with emojis EXCEPT for IAM:
- For S3 Buckets: "🪣 S3 BUCKETS IN {region_name} 🪣"
- For S3 Objects: "📁 S3 OBJECTS IN BUCKET [bucket-name] 📁"
- For EC2: "🖥️ EC2 INSTANCES IN {region_name} 🖥️"
- For Lambda: "⚡ LAMBDA FUNCTIONS IN {region_name} ⚡"
- For RDS: "🗄️ RDS INSTANCES IN {region_name} 🗄️"
- For IAM Users: "👥 IAM USERS (GLOBAL) 👥"
- For IAM Roles: "🎭 IAM ROLES (GLOBAL) 🎭"

Format tables like:
Instance ID        | Type     | State   | Name           | Launch Date
------------------|----------|---------|----------------|-------------
i-1234567890abcdef0 | t3.micro | running | web-server     | Jan 20, 2024

Summary with count and status
Helpful tip or insight

ABSOLUTE REQUIREMENTS:
- NEVER show <thinking> tags or reasoning process
- NEVER show raw JSON or internal processing
- Always use friendly tables with emojis and insights
- IAM services are GLOBAL - never include region names in IAM headers
- Use "(GLOBAL)" for all IAM-related responses
- START every response with emoji headers immediately
"""

class QueryRequest(BaseModel):
    query: str
    aws_region: Optional[str] = "ap-southeast-2"

@app.get('/health')
def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}

@app.post('/aws-query-streaming')
async def query_aws_resources_streaming(request: QueryRequest):
    """Endpoint to stream AWS query results."""
    try:
        query = request.query
        region = request.aws_region or "ap-southeast-2"

        if not query:
            raise HTTPException(status_code=400, detail="No query provided")

        async def stream_aws_response():
            from aws_tool import use_aws, set_session
            set_session(boto3.Session(), region)

            aws_agent = Agent(
                model=bedrock_model,
                system_prompt=get_aws_system_prompt(region),
                tools=[use_aws],
            )

            async for item in aws_agent.stream_async(query):
                if "data" in item:
                    yield mask_aws_account_numbers(item['data'])

        return StreamingResponse(
            stream_aws_response(),
            media_type="text/plain"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == '__main__':
    # Get port from environment variable or default to 9083
    port = int(os.environ.get('PORT', 9083))
    # Check if we're in a virtual environment or development mode
    if os.environ.get('VIRTUAL_ENV') or '--reload' in sys.argv:
        uvicorn.run("aws_agent:app", host='0.0.0.0', port=port, reload=True)
    else:
        uvicorn.run(app, host='0.0.0.0', port=port)