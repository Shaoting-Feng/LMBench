from ray import serve
import os
import traceback
import logging

# Configure logging
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("fruit")

class FruitModel:
    def __init__(self, model_url, hf_token=None):
        self.model_url = model_url
        self.hf_token = hf_token
        self.setup()
        self.fruit_prices = {
            "APPLE": 1,
            "BANANA": 2,
            "ORANGE": 3,
            "MANGO": 3,
            "STRAWBERRY": 4
        }

    def setup(self):
        # For debugging, we're using a simple fruit price model
        # This avoids GPU loading issues in debug mode
        logger.info(f"Setting up fruit stand with model reference: {self.model_url}")

    async def __call__(self, request):
        try:
            # Get the data from the request
            data = await request.json()
            logger.info(f"Received request with data: {data}")

            # Extract fruit and quantity
            fruit, quantity = data

            # Calculate the total price
            price_per_unit = self.fruit_prices.get(fruit, 1)
            total_price = price_per_unit * quantity

            logger.info(f"Calculated total price {total_price} for {quantity} of {fruit}")
            return total_price
        except Exception as e:
            error_msg = f"Error processing request: {str(e)}\n{traceback.format_exc()}"
            logger.error(error_msg)
            return {"error": str(e)}

@serve.deployment
class FruitStand:
    def __init__(self):
        logger.info("Initializing FruitStand")
        model_url = os.environ.get("MODEL_URL", "meta-llama/Llama-3.1-8B-Instruct")
        hf_token = os.environ.get("HF_TOKEN", None)
        logger.info(f"Using model URL: {model_url}")
        self.model = FruitModel(model_url, hf_token)
        logger.info("FruitStand initialized successfully")

    async def __call__(self, request):
        try:
            return await self.model(request)
        except Exception as e:
            error_msg = f"Error in FruitStand: {str(e)}\n{traceback.format_exc()}"
            logger.error(error_msg)
            return {"error": str(e)}

# Initialize the deployment
try:
    logger.info("Starting FruitStand deployment")
    deployment = FruitStand.bind()
    logger.info("FruitStand deployment started")
except Exception as e:
    logger.error(f"Failed to start deployment: {str(e)}\n{traceback.format_exc()}")
    raise