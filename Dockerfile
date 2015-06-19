FROM umegaya/luact@sha256:1c595aacf92d7c4401a76b0d13f0be70abbc98dd7795289cd2dbe2fadb5e316f
ENV LD_PRELOAD=libpthread.so.0
ADD . /lunarsurface
ADD ./yue /usr/local/bin/yue
RUN chmod 755 /usr/local/bin/yue
RUN cd /lunarsurface && git reset --hard
RUN rm -r /root/.ssh && cp -r /lunarsurface/.yue/certs /root/.ssh && chmod 600 /root/.ssh/id_rsa /root/.ssh/*key.pem
CMD bash -c "cd /lunarsurface && luajit-2.1.0-alpha -e 'require([[jit.opt]]).start([[minstitch=10000]])' -e 'package.path=[[/luact/?.lua;]]..package.path' /luact/run.lua --logdir=/lunarsurface/logs --datadir=/lunarsurface/data --ssl.pubkey=.yue/certs/server.pem --ssl.privkey=.yue/certs/server-key.pem --deploy.method=gitlab.com src/main.lua"
