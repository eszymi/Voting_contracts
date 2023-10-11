import random
import sys
import json
from eth_hash.auto import keccak

arguments = sys.argv


how_many_number = 128


# The first value (arguments[0] is the name of the script)
if len(arguments) > 1:
    how_many_number = int(arguments[1])


minimal_value = 1
maximal_value = 100000


file_name = "random_hashes.json"
hashes = []


for _ in range(how_many_number):
    random_number = str(random.randint(minimal_value, maximal_value)).encode("utf-8")
    sha256_hash = keccak(random_number)
    hashes.append("0x" + str(sha256_hash.hex()))

json_hashes = json.dumps(hashes)

with open(file_name, "w") as file:
    file.write(json_hashes)

print(
    f"File {file_name} has been created and fulfiled by {how_many_number} random numbers."
)
