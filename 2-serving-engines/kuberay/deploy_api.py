#!/usr/bin/env python
import ray
import logging
import os
import sys

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("ray_deploy")

# Initialize Ray
if ray.is_initialized():
    logger.info('Ray is already initialized')
else:
    logger.info('Initializing Ray...')
    ray.init()

# Start Ray Serve
from ray import serve

logger.info('Starting Ray Serve...')
serve.start(detached=True, http_options={'host': '0.0.0.0', 'port': 8000})

# Import the API class
sys.path.append('/home/ray')
from api import OpenAICompatibleAPI

# Deploy the API
logger.info('Deploying API...')
handle = serve.run(OpenAICompatibleAPI.bind(), route_prefix="/v1")

logger.info('API deployed successfully!')