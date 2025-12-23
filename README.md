## Installing NeMo Microservices on OpenShift AI:

See this [repo](https://github.com/RHEcosystemAppEng/NeMo-Microservices) for the final product.

1. Verify the Hardware and Software [Requirements](https://docs.nvidia.com/nemo/microservices/latest/requirements.html?utm_source=chatgpt.com) for NeMo Microservices
2. Follow the [prerequisites](https://docs.nvidia.com/nim-operator/latest/nemo-prerequisites.html) instruction, and create `.env` file with the following fields:
    ```
    NGC_API_KEY="<your_Nvidia_key>"
    HF_Token="<your_HF_key>"
    ```
3. Clone this git [repository](https://github.com/rhkp/k8s-nim-operator/tree/deploy-v3.0-on-openshift?tab=readme-ov-file) to this working directory.
4. Connect to your OpenShift cluster.
5. Run the commands:
    ```
    chmod +x clear_namespace.sh
    chmod +x nemo_prerequisites.sh
    chmod +x deploy_microservices.sh
    chmod +x run.sh
    ```
6. Update the `NAMESPACE` variable in script `run.sh` script.
7. Run `bash run.sh`
8. Track the installation on your cluster.

---
## To deploy NIM:

1. Enable NIM oprertor on OpenShift AI.
2. Verify the existance of GPUs with
    ```
    oc get nodes -o json | jq -r '.items[] | select(.spec.taints != null) | {name: .metadata.name, taints: .spec.taints}'
    ```
3. Use `llama-num.yaml` to deploy the LLM using this might take about 10-15 minutes to complete, track the pod's events to make sure that there are no errors (for example authentication error)
    ```
    oc apply -f llama-nim.yaml
    ```

---

## Jupyter Notebook

1. Expose service:
    ```
    oc expose svc jupyter-service
    ```
    or expose the pod:
    ```
    oc expose pod jupyter-notebook-b7d5479dd-rx8v7 --port=8888 --name=jupyter-notebook-service
    ```
2. Get the route (use http no https)
    ```
    oc get route
    ```
3. Get token via the pod:
    ```
    oc exec jupyter-notebook-b7d5479dd-rx8v7 -- jupyter server list
    ```
    the output would look like:
    ```
    Currently running servers:
    http://jupyter-notebook-b7d5479dd-rx8v7:8888/?token=token :: /home/jovya
    ```
    so in my case the token is simply "token".


