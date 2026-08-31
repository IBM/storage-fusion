# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
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
"""
IBM Fusion CAS (Content Augmented Search) NAT retriever.

Registers _type: fusion_cas for the retrievers: section of any workflow YAML.
"""

from .adapter import FusionCASRetriever
from .adapter import FusionCASRetrieverConfig
from .adapter import fusion_cas_retriever_client
from .adapter import fusion_cas_retriever_provider

__all__ = ["FusionCASRetriever", "FusionCASRetrieverConfig", "fusion_cas_retriever_client", "fusion_cas_retriever_provider"]
