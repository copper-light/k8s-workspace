import airflow
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime

dag = DAG(
    dag_id = "handh_first_dag",
    start_date=datetime(2021, 1, 1),
    schedule_interval=None,
)
work1 = BashOperator(
    task_id = "bash01",
    bash_command="echo 'work1'",
    dag = dag,
)

work2 = BashOperator(
    task_id = "bash02",
    bash_command="echo 'work1'",
    dag = dag,
)

work3 = BashOperator(
    task_id = "bash03",
    bash_command="echo 'work3'",
    dag = dag,
)

work1 >> work2 >> work3