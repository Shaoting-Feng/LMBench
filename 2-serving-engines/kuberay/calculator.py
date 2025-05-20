from ray import serve
import os
import traceback
import logging

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("calculator")

class CalculatorModel:
    def __init__(self, model_url, hf_token=None):
        self.model_url = model_url
        self.hf_token = hf_token
        self.setup()

    def setup(self):
        # For debugging, we're using a simple calculator model
        # This avoids GPU loading issues in debug mode
        logger.info(f"Setting up calculator with model reference: {self.model_url}")

    async def __call__(self, request):
        try:
            # Get the data from the request
            data = await request.json()
            logger.info(f"Received request with data: {data}")

            # Extract operation and number
            operation, number = data
            result = 0

            if operation == "ADD":
                result = number + 5
            elif operation == "SUB":
                result = number - 5
            elif operation == "MUL":
                result = number * 5
            elif operation == "DIV":
                result = number / 5

            response = f"{result} pizzas please!"
            logger.info(f"Calculated result for {operation} {number}: {response}")
            return response
        except Exception as e:
            error_msg = f"Error processing request: {str(e)}\n{traceback.format_exc()}"
            logger.error(error_msg)
            return {"error": str(e)}

@serve.deployment
class Calculator:
    def __init__(self):
        logger.info("Initializing Calculator")
        model_url = os.environ.get("MODEL_URL", "meta-llama/Llama-3.1-8B-Instruct")
        hf_token = os.environ.get("HF_TOKEN", None)
        logger.info(f"Using model URL: {model_url}")
        self.model = CalculatorModel(model_url, hf_token)
        logger.info("Calculator initialized successfully")

    async def __call__(self, request):
        try:
            return await self.model(request)
        except Exception as e:
            error_msg = f"Error in Calculator: {str(e)}\n{traceback.format_exc()}"
            logger.error(error_msg)
            return {"error": str(e)}

# Initialize the deployment
try:
    logger.info("Starting Calculator deployment")
    deployment = Calculator.bind()
    logger.info("Calculator deployment started")
except Exception as e:
    logger.error(f"Failed to start deployment: {str(e)}\n{traceback.format_exc()}")
    raise