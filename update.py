# -*- coding: utf-8 -*-
# Upside Travel, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os

import boto3

import clamav

from common import AV_CUSTOM_DEFINITION_FILES_PATH
from common import AV_DEFINITION_PATH
from common import AV_DEFINITION_S3_BUCKET
from common import AV_DEFINITION_S3_PREFIX
from common import CLAMAVLIB_PATH
from common import get_timestamp
from datetime import datetime
import shutil


def lambda_handler(event, context):
    s3_client = boto3.client("s3")

    start_time = datetime.utcnow()
    print("Script starting at %s\n" % (start_time.strftime("%Y/%m/%d %H:%M:%S UTC")))

    if os.path.isdir(AV_DEFINITION_PATH):
        shutil.rmtree(AV_DEFINITION_PATH)
        os.mkdir(AV_DEFINITION_PATH)

    print("Skipping clamav definition download %s\n" % (get_timestamp()))

    retVal = clamav.update_defs_from_freshclam(AV_DEFINITION_PATH, CLAMAVLIB_PATH)
    if retVal != 0:
        raise RuntimeError("clamAV update process returned %d" % (retVal))
    
    # If main.cvd gets updated (very rare), we will need to force freshclam
    # to download the compressed version to keep file sizes down.
    # The existence of main.cud is the trigger to know this has happened.
    if os.path.exists(os.path.join(AV_DEFINITION_PATH, "main.cud")):
        os.remove(os.path.join(AV_DEFINITION_PATH, "main.cud"))
        if os.path.exists(os.path.join(AV_DEFINITION_PATH, "main.cvd")):
            os.remove(os.path.join(AV_DEFINITION_PATH, "main.cvd"))
        retVal = clamav.update_defs_from_freshclam(AV_DEFINITION_PATH, CLAMAVLIB_PATH)
        if retVal != 0:
            raise RuntimeError("Refresh clamAV update process returned %d" % (retVal))

    # Copying our custom definition files to clamav default definitions path.
    for filename in os.listdir(AV_CUSTOM_DEFINITION_FILES_PATH):
        shutil.copy(os.path.join(AV_CUSTOM_DEFINITION_FILES_PATH, filename), AV_DEFINITION_PATH)

    clamav.upload_defs_to_s3(
        s3_client, AV_DEFINITION_S3_BUCKET, AV_DEFINITION_S3_PREFIX, AV_DEFINITION_PATH
    )
    print("Script finished at %s\n" % get_timestamp())
