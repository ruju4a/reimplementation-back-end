FROM ruby:3.4.5

LABEL maintainer="Ankur Mundra <ankurmundra0212@gmail.com>"

WORKDIR /app

COPY . .

# Install gems from vendor/cache — no network access required
RUN bundle install --local

EXPOSE 3002

ENTRYPOINT ["/app/setup.sh"]