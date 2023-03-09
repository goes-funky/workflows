FROM ghcr.io/cicirello/pyaction:4.16.0

RUN pip install poetry

COPY run_poetry.py /run_poetry.py
RUN chmod +x run_poetry.py
ENTRYPOINT ["/run_poetry.py"]
