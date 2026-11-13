# Веб-версия игры для CapRover: nginx отдаёт готовую сборку Godot (папка web/ кладётся рядом при деплое).
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY web/ /usr/share/nginx/html/
# заранее сжатые копии: nginx отдаёт .gz сам (gzip_static), не тратя процессор на каждый запрос
RUN cd /usr/share/nginx/html && gzip -k -9 index.wasm index.pck index.js index.html     && cd compat && gzip -k -9 index.wasm index.pck index.js index.html
