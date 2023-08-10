FROM node:16
# Create app directory
WORKDIR /usr/src/app
# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./
# RUN npm install
RUN npm install -g @cloudant/couchbackup
# Bundle app source
RUN apt-get update -y
RUN apt-get install dnsutils -y
RUN apt-get install traceroute -y
COPY . .
EXPOSE 5984/tcp
ENTRYPOINT ["tail", "-f", "/dev/null"]
CMD [ "npm", "start" ]
