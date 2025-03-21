import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2_client = boto3.client('ec2')
    logger.info(f"Event received: {json.dumps(event, indent=2)}")

    try:
        if event.get('httpMethod') == 'GET':
            logger.info("Handling GET request to list instances")
            response = ec2_client.describe_instances()
            instances = []
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    name = next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed')
                    instances.append({
                        'InstanceId': instance['InstanceId'],
                        'Name': name,
                        'InstanceType': instance['InstanceType'],
                        'State': instance['State']['Name']
                    })
            logger.info(f"Returning {len(instances)} instances")
            return {
                'statusCode': 200,
                'body': json.dumps(instances),
                'headers': {'Content-Type': 'application/json'}
            }

        elif event.get('httpMethod') == 'POST':
            body = json.loads(event.get('body', '{}'))
            action = event['path'].split('/')[-1]
            # Handle both single instanceId and array instanceIds
            instance_ids = body.get('instanceIds', [])
            if not instance_ids and body.get('instanceId'):
                instance_ids = [body.get('instanceId')]
            # Filter out falsy values (e.g., None, empty string)
            instance_ids = [id for id in instance_ids if id]

            logger.info(f"Handling POST request: Action={action}, InstanceIDs={instance_ids}")

            # Handle /start and /stop (existing logic)
            if action in ['start', 'stop']:
                if not instance_ids:
                    logger.error(f"Validation failed: InstanceIDs={instance_ids}, Action={action}")
                    return {
                        'statusCode': 400,
                        'body': json.dumps({'error': 'Missing instanceIds'})
                    }

                if action == 'start':
                    logger.info(f"Starting instances: {instance_ids}")
                    ec2_client.start_instances(InstanceIds=instance_ids)
                    logger.info(f"Successfully started instances: {instance_ids}")
                elif action == 'stop':
                    logger.info(f"Stopping instances: {instance_ids}")
                    ec2_client.stop_instances(InstanceIds=instance_ids)
                    logger.info(f"Successfully stopped instances: {instance_ids}")

                return {
                    'statusCode': 200,
                    'body': json.dumps({'message': f'{action.capitalize()}ed instances {instance_ids}'})
                }

            # Handle /tag (new logic)
            elif action == 'tag':
                if not instance_ids:
                    logger.error(f"Validation failed: InstanceIDs={instance_ids}, Action={action}")
                    return {
                        'statusCode': 400,
                        'body': json.dumps({'error': 'Missing instanceIds'})
                    }

                shift = body.get('shift', 'None')  # Default to 'None' if shift is not provided
                logger.info(f"Tagging instances {instance_ids} with Shift={shift}")

                # Tag the EC2 instances
                ec2_client.create_tags(
                    Resources=instance_ids,
                    Tags=[
                        {
                            'Key': 'Shift',
                            'Value': shift
                        }
                    ]
                )

                logger.info(f"Successfully tagged instances {instance_ids} with Shift={shift}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'message': f'Successfully tagged instances with Shift={shift}'})
                }

            else:
                logger.error(f"Invalid action: {action}")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': f'Invalid action: {action}'})
                }

    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
