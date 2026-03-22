#!/usr/bin/env python3
"""Test SSM implementation"""
import sys
sys.path.insert(0, 'backend')
from mock_strands import MockAgent

# Create mock tools
def list_s3_buckets():
    return 'S3 data'

def list_ssm_parameters(query):
    return f'SSM Parameters data for query: {query}'

def list_dynamodb_tables(query):
    return 'DynamoDB data'

# Set function names
list_ssm_parameters.__name__ = 'list_ssm_parameters'
list_s3_buckets.__name__ = 'list_s3_buckets'
list_dynamodb_tables.__name__ = 'list_dynamodb_tables'

agent = MockAgent(
    model=None,
    system_prompt='Test',
    tools=[list_s3_buckets, list_ssm_parameters, list_dynamodb_tables]
)

print('\n' + '='*70)
print('✅ TEST 1: SSM Parameters Query')
print('='*70)
result = agent('Show me SSM parameters')
print(result)
print()

print('='*70)
print('✅ TEST 2: SSM with "config" keyword')
print('='*70)
result = agent('List system manager configuration parameters')
print(result)
print()

print('='*70)
print('✅ TEST 3: S3 Query (should still work)')
print('='*70)
result = agent('Show S3 buckets')
print(result)
print()

print('='*70)
print('✅ TEST 4: Unsupported Service (DynamoDB)')
print('='*70)
result = agent('Show me DynamoDB tables')
print(result)
