FROM node:18

# Install dependencies for Foundry
RUN apt-get update && \
    apt-get install -y curl build-essential git && \
    apt-get clean

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash && \
    ~/.foundry/bin/foundryup

# Add Foundry binaries to PATH
ENV PATH="/root/.foundry/bin:${PATH}"

WORKDIR /app

COPY . .

RUN forge install

RUN cd manager && npm install

RUN cd manager && npm run build

CMD ["sh", "-c", "cd /app/manager && node --experimental-specifier-resolution=node dist/index.js"]