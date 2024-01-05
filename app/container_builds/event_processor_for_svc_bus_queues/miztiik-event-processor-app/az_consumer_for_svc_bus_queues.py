import json
import logging
import time
import os
import isodate
import datetime

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient

# ANSI color codes
GREEN_COLOR = "\033[32m"
RED_COLOR = "\033[31m"
RESET_COLOR = "\033[0m"

# Example usage with logging
logging.getLogger().setLevel(logging.INFO)
logging.info(f'{GREEN_COLOR}Miztiik Automation In Progress{RESET_COLOR}')


class GlobalArgs:
    OWNER = "Mystique"
    VERSION = "2023-06-28"
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
    EVNT_WEIGHTS = {"success": 80, "fail": 20}
    TRIGGER_RANDOM_FAILURES = os.getenv("TRIGGER_RANDOM_FAILURES", True)
    WAIT_SECS_BETWEEN_MSGS = int(os.getenv("WAIT_SECS_BETWEEN_MSGS", 2))
    TOT_MSGS_TO_PRODUCE = int(os.getenv("TOT_MSGS_TO_PRODUCE", 2))
    MAX_MSGS_TO_PROCESS = int(os.getenv("MAX_MSGS_TO_PROCESS", 5))

    SA_NAME = os.getenv("SA_NAME", "warehousehuscgs003")
    BLOB_SVC_ACCOUNT_URL = os.getenv(
        "BLOB_SVC_ACCOUNT_URL", "https://warehousehuscgs003.blob.core.windows.net")
    BLOB_NAME = os.getenv("BLOB_NAME", "store-events-blob-003")
    BLOB_PREFIX = "store_events/processed"

    COSMOS_DB_URL = os.getenv(
        "COSMOS_DB_URL", "https://partition-processor-db-account-003.documents.azure.com:443/")
    COSMOS_DB_NAME = os.getenv(
        "COSMOS_DB_NAME", "partition-processor-db-account-003")
    COSMOS_DB_CONTAINER_NAME = os.getenv(
        "COSMOS_DB_CONTAINER_NAME", "store-backend-container-003")

    SVC_BUS_FQDN = os.getenv(
        "SVC_BUS_FQDN", "warehouse-ne-svc-bus-ns-container-apps-005.servicebus.windows.net")
    SVC_BUS_Q_NAME = os.getenv("SVC_BUS_Q_NAME", "warehouse-q-005")


def read_from_svc_bus_q(max_messages=GlobalArgs.MAX_MSGS_TO_PROCESS):
    _r = {
        "status": False,
        "event_process_duration": 0,
        "max_msg_count": max_messages,
        "processed_msg_count": 0,
    }
    # Start timing the event generation
    event_process_start_time = time.time()

    # Setup up Azure Credentials
    azure_log_level = logging.getLogger("azure").setLevel(logging.ERROR)
    default_credential = DefaultAzureCredential(
        logging_enable=False, logging=azure_log_level)

    blob_svc_client = BlobServiceClient(
        GlobalArgs.BLOB_SVC_ACCOUNT_URL, credential=default_credential, logging=azure_log_level)

    cosmos_client = CosmosClient(
        url=GlobalArgs.COSMOS_DB_URL, credential=default_credential)
    db_client = cosmos_client.get_database_client(
        GlobalArgs.COSMOS_DB_NAME)
    db_container = db_client.get_container_client(
        GlobalArgs.COSMOS_DB_CONTAINER_NAME)

    with ServiceBusClient(GlobalArgs.SVC_BUS_FQDN, credential=default_credential) as client:
        with client.get_queue_receiver(GlobalArgs.SVC_BUS_Q_NAME) as receiver:
            backoff_time = 1
            max_backoff_time = 3600  # maximum backoff time in seconds
            message_count = 1
            while message_count < max_messages:
                try:
                    recv_msgs = receiver.receive_messages(
                        max_message_count=1, max_wait_time=5)
                    if not recv_msgs:
                        logging.info(
                            f"No messages received. Current backoff time: {backoff_time} seconds. Time to reset: {max_backoff_time - backoff_time} seconds.")
                        print(
                            f"No messages received. Current backoff time: {backoff_time} seconds. Time to reset: {max_backoff_time - backoff_time} seconds.")
                        time.sleep(backoff_time)
                        # exponential backoff with maximum
                        backoff_time = min(backoff_time * 2, max_backoff_time)
                    else:
                        backoff_time = 1  # reset backoff time on successful receive
                    recv_event = {}
                    for msg in recv_msgs:
                        recv_event['id'] = msg.message_id
                        recv_event['body'] = json.loads(str(msg))
                        recv_event['content_type'] = msg.content_type
                        recv_event['delivery_count'] = msg.delivery_count
                        recv_event['partition_key'] = msg.partition_key
                        recv_event['reply_to'] = msg.reply_to
                        recv_event['reply_to_session_id'] = msg.reply_to_session_id
                        recv_event['session_id'] = msg.session_id
                        recv_event['time_to_live'] = isodate.duration_isoformat(
                            msg.time_to_live)
                        recv_event['to'] = msg.to
                        recv_event['user_properties'] = {key.decode(): value.decode(
                        ) for key, value in msg.application_properties.items()}
                        recv_event['event_type'] = recv_event['user_properties'].get(
                            'event_type')
                        print(
                            f"Received: {message_count} of {max_messages} messages. Current backoff time: {backoff_time} seconds. Time to reset: {max_backoff_time - backoff_time} seconds.")
                        # print(f"{recv_event}")

                        # Write to blob
                        write_to_blob(
                            recv_event['event_type'], recv_event, blob_svc_client)

                        # Write to Cosmos DB
                        write_to_cosmosdb(recv_event, db_container)

                        receiver.complete_message(msg)
                        message_count += 1
                except Exception as e:
                    print(f"Empty Receive from Queue: {e}")
                    logging.error(f"Error receiving message: {e}")
    event_process_end_time = time.time()  # Stop timing the event generation
    event_process_duration = event_process_end_time - \
        event_process_start_time  # Calculate the duration
    _r["status"] = True
    _r["event_process_duration"] = event_process_duration
    _r["processed_msg_count"] = message_count
    print(
        f"Received: {message_count} of {max_messages} messages. Max msg count reached, exiting")
    return _r


def write_to_blob(container_prefix: str, data: dict, blob_svc_client):
    try:
        blob_name = f"{GlobalArgs.BLOB_PREFIX}/event_type={container_prefix}/dt={datetime.datetime.now().strftime('%Y_%m_%d')}/{datetime.datetime.now().strftime('%s%f')}.json"
        if container_prefix is None:
            blob_name = f"{GlobalArgs.BLOB_PREFIX}/dt={datetime.datetime.now().strftime('%Y_%m_%d')}/{datetime.datetime.now().strftime('%s%f')}.json"

        blob_client = blob_svc_client.get_blob_client(
            container=GlobalArgs.BLOB_NAME, blob=blob_name)

        if blob_client.exists():
            blob_client.delete_blob()
            logging.debug(
                f"Blob {blob_name} already exists. Deleted the file.")

        resp = blob_client.upload_blob(json.dumps(data).encode("UTF-8"))
        logging.info(
            f"Blob {GREEN_COLOR}{blob_name}{RESET_COLOR} uploaded successfully")
        logging.debug(f"{resp}")
    except Exception as e:
        logging.exception(f"ERROR:{str(e)}")


def write_to_cosmosdb(data: dict, db_container):
    try:
        resp = db_container.create_item(body=data)
        logging.info(
            f"Document with id {GREEN_COLOR}{data['id']}{RESET_COLOR} written to CosmosDB successfully")
        logging.debug(f"{resp}")
    except Exception as e:
        logging.exception(f"ERROR:{str(e)}")


if __name__ == "__main__":
    read_from_svc_bus_q()
