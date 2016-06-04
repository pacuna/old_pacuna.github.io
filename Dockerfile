FROM jekyll/jekyll:2.5
COPY . /srv/jekyll
RUN chown -R jekyll:jekyll /srv/jekyll
EXPOSE 4000
