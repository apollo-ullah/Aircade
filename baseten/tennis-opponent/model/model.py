import json
import math
from pathlib import Path


class Model:
    """Small candidate-return model served through a Baseten Truss endpoint."""

    def __init__(self, **_kwargs):
        self.parameters = None

    def load(self):
        weights_path = Path(__file__).with_name("weights.json")
        self.parameters = json.loads(weights_path.read_text())

    def predict(self, request):
        if self.parameters is None:
            self.load()
        candidates = request.get("candidates")
        if not isinstance(candidates, list) or not 3 <= len(candidates) <= 12:
            raise ValueError("candidates must contain between 3 and 12 legal returns")

        weights = self.parameters["weights"]
        predictions = []
        for candidate in candidates:
            logit = self.parameters["bias"]
            logit += weights["distance"] * float(candidate["distance"])
            logit += weights["reactionTime"] * float(candidate["reactionTime"])
            logit += weights["pace"] * float(candidate["pace"])
            logit += weights["targetsWeakSide"] * float(bool(candidate["targetsWeakSide"]))
            logit += weights["rallyLength"] * min(float(candidate["rallyLength"]), 20.0)
            probability = 1.0 / (1.0 + math.exp(-max(-20.0, min(20.0, logit))))
            predictions.append({"id": candidate["id"], "returnProbability": probability})

        return {
            "modelVersion": self.parameters["modelVersion"],
            "predictions": predictions,
        }
