import boto3
import json

def list_ec2_instances():
    ec2_client = boto3.client('ec2')
    regions = [region['RegionName'] for region in ec2_client.describe_regions()['Regions']]
    instances = []

    for region in regions:
        ec2 = boto3.client('ec2', region_name=region)
        response = ec2.describe_instances()
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                # Get instance name from tags
                name = 'N/A'
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        name = tag['Value']
                        break
                instances.append({
                    'InstanceId': instance['InstanceId'],
                    'Name': name,
                    'Region': region,
                    'State': instance['State']['Name'],  # Instance state (e.g., 'running', 'stopped')
                    'InstanceType': instance['InstanceType']  # Add instance type (e.g., 't2.micro')
                })
    return instances

def perform_ec2_action(action, instance_id, region):
    ec2_client = boto3.client('ec2', region_name=region)
    try:
        if action == 'start':
            ec2_client.start_instances(InstanceIds=[instance_id])
            return f"Started EC2 instance {instance_id} in {region}"
        elif action == 'stop':
            ec2_client.stop_instances(InstanceIds=[instance_id])
            return f"Stopped EC2 instance {instance_id} in {region}"
    except Exception as e:
        return f"Error performing EC2 action: {e}"

def lambda_handler(event, context):
    # Parse the request
    body = json.loads(event.get('body', '{}'))
    operation = body.get('operation')

    if operation == 'list_instances':
        # Return list of EC2 instances
        instances = list_ec2_instances()
        return {
            'statusCode': 200,
            'body': json.dumps(instances)
        }
    elif operation == 'perform_action':
        # Perform start/stop action
        action = body.get('action')
        instance_id = body.get('instance_id')
        region = body.get('region')
        result = perform_ec2_action(action, instance_id, region)
        return {
            'statusCode': 200,
            'body': json.dumps(result)
        }
    else:
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid operation')
        }
