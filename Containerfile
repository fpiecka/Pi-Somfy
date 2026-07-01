FROM python:3.14-slim AS build

ARG LG_REPO=https://github.com/joan2937/lg.git
ARG PIGPIO_REPO=https://github.com/joan2937/pigpio.git

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        make \
        gcc \
        g++ \
        libc6-dev \
        swig \
        python3-dev \
    && python -m venv "${VIRTUAL_ENV}" \
    && pip install --no-cache-dir --upgrade pip setuptools wheel \
    && git clone --depth 1 "${LG_REPO}" /tmp/lg \
    && make -C /tmp/lg \
    && make -C /tmp/lg install \
    && pip install --no-cache-dir /tmp/lg/PY_LGPIO \
    && git clone --depth 1 "${PIGPIO_REPO}" /tmp/pigpio \
    && make -C /tmp/pigpio \
    && make -C /tmp/pigpio install

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
ENV PI_SOMFY_CONFIG=/data/operateShutters.conf
ENV PI_SOMFY_ARGS="-a"
ENV PI_SOMFY_ALLOW_NON_ROOT=true

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        procps \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 pi-somfy \
    && useradd --system --uid 10001 --gid pi-somfy --home-dir /app --shell /usr/sbin/nologin pi-somfy \
    && mkdir -p /app /data /var/log \
    && chown -R pi-somfy:pi-somfy /app /data /var/log

COPY --from=build /opt/venv /opt/venv
COPY --from=build /usr/local /usr/local
COPY . /app
RUN sed -i \
        -e 's/^LogToFile = true/LogToFile = false/' \
        -e 's/^LogToConsole = false/LogToConsole = true/' \
        -e 's/^HTTPPort = 80/HTTPPort = 8080/' \
        -e 's/^PigpioHost =/PigpioHost = pigpiod/' \
        /app/defaultConfig.conf \
    && chown -R pi-somfy:pi-somfy /app

WORKDIR /app
VOLUME ["/data"]
EXPOSE 8080

USER pi-somfy

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/cmd/getConfig >/dev/null || exit 1

CMD ["sh", "-c", "exec python3 /app/operateShutters.py -c \"$PI_SOMFY_CONFIG\" $PI_SOMFY_ARGS"]
