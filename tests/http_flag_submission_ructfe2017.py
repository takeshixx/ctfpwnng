#!/usr/bin/env python3
# A simple web application that mimics the
# new flag submission HTTP API of RuCTFE 2017.
import random
import json
import re
from flask import Flask, request, jsonify
app = Flask(__name__)

FLAG_REGEX = re.compile(r'\w{31}=')
TRUE_MSG = ["Accepted. 1.73205080756888 flag points"] 
FALSE_MSG = ["Denied: no such flag",
             "Denied: flag is your own",
             "Denied: you already submitted this flag"]


@app.route('/flags', methods=['GET', 'PUT'])
def flags():
    if request.method == 'GET':
        return "Send flags via PUT request"
    data = request.stream.read()
    print(data)
    try:
        input_flags = json.loads(data)
    except Exception as e:
        print(e)
        return "Parsing input json failed"
    ret = []
    if not input_flags:
        print("Received no flags")
        return "No flags provided"
    else:
        for f in input_flags:
            _f = {}
            _f['flag'] = f
            if not FLAG_REGEX.findall(f):
                _f['msg'] = '[' + f + '] Invalid flag'
                _f['status'] = False
                ret.append(_f)
                continue
            resp = random.choice([True, False])
            if resp:
                _f['msg'] = '[' + f + '] ' + TRUE_MSG[0]
                _f['status'] = True
            else:
                _f['msg'] = '[' + f + '] ' + random.choice(FALSE_MSG)
                _f['status'] = False
            ret.append(_f)
        return jsonify(ret)
            

if __name__ == '__main__':
    app.run()
