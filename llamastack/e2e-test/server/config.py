NDS_URL = "http://localhost:8001"  # Data Store
ENTITY_STORE_URL = "http://localhost:8002"  # Entity Store
CUSTOMIZER_URL = "http://localhost:8003"  # Customizer
EVALUATOR_URL = "http://localhost:8004"  # Evaluator
GUARDRAILS_URL = "http://localhost:8005"  # Guardrails
DATA_STORE_URL = NDS_URL 
NIM_URL = "http://localhost:8006"  # NIM
NEMO_URL = "http://localhost:8007"
LLAMASTACK_URL= "http://localhost:8321"
# (Required) Hugging Face Token
HF_TOKEN = ""

# (Optional) To observe training with WandB
WANDB_API_KEY = ""

# (Optional) Modify if you've configured a NeMo Data Store token
NDS_TOKEN = "token"

# (Optional) Use a dedicated namespace and dataset name for tutorial assets
NMS_NAMESPACE = "xlam-tutorial-ns"
DATASET_NAME = "xlam-ft-dataset"

# (Optional) Configure the base model. Must be one supported by the NeMo Customizer deployment!
BASE_MODEL = "meta/llama-3.2-1b-instruct"
BASE_MODEL_VERSION = "v1.0.0+A100"
# (Optional) Entity Store Project ID. Modify if you've created a project in Entity Store that you'd
# like to associate with your Customized models.
PROJECT_ID = ""
# (Optional) Directory to save the Customized model.
CUSTOMIZED_MODEL_DIR = "nvidia-tool-calling-tutorial/test-llama-stack@v1"

# (Optional) Modify if you've configured a NeMo Data Store token
NDS_TOKEN = "token"