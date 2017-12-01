#!/usr/bin/env python2
"""A simple gameserver that returns random
states for submitted flags."""
import sys
import socket
import re
from random import choice
from threading import Thread
import time

states = [b'expired', b'no such flag', b'accepted', b'corresponding', b'own flag']
flag_grep = re.compile(br"(\w{31}=)")


def clientthread(conn, addr):
    conn.send(b'Welcome to the gameserver and stuff\n')
    print('New connection from {}'.format(addr[0]))
    flags = []
    while True:
        try:
            data = conn.recv(1024)
            flags += flag_grep.findall(data)
            if not flags:
                conn.send(states[1])
            else:
                resp = choice(states)
                conn.send(resp+b'\n')
        except Exception as e:
            print('Received {} flags'.format(len(flags)))
            print(e)
            conn.close()
            return

while True:
    try:
        sock = socket.socket()
        sock.bind(('127.0.0.1', 9000))
        sock.listen(10)
        print("Gameserver is up and listening")
        while True:
            conn, addr = sock.accept()
            t = Thread(target=clientthread,
                       args=(conn, addr))
            t.start()
    except KeyboardInterrupt:
        sock.close()
        sys.exit(0)
    except IOError as e:
        print(str(e))
        if e.errno == 98:
            print("Sleeping 5s")
            time.sleep(5)
    except Exception as e:
        print(str(e))
