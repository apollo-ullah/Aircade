#!/usr/bin/env python3
"""Fit the first policy from deterministic synthetic exchanges.

This deliberately uses no third-party packages so the hackathon baseline is
reproducible. Replace the generated examples with consenting tennis telemetry
without changing the Truss prediction contract.
"""

import json
import math
import random
from pathlib import Path

FEATURES = ("distance", "reactionTime", "pace", "targetsWeakSide", "rallyLength")
TRUTH = {"bias": 2.2, "distance": -1.55, "reactionTime": 1.35,
         "pace": -0.9, "targetsWeakSide": -0.62, "rallyLength": -0.028}


def sigmoid(value):
    return 1.0 / (1.0 + math.exp(-max(-20.0, min(20.0, value))))


def example(rng):
    row = {
        "distance": rng.uniform(0, 1.2),
        "reactionTime": rng.uniform(0.85, 1.65),
        "pace": rng.uniform(0.55, 1.2),
        "targetsWeakSide": float(rng.random() < 0.5),
        "rallyLength": float(rng.randrange(0, 21)),
    }
    probability = sigmoid(TRUTH["bias"] + sum(TRUTH[name] * row[name] for name in FEATURES))
    return row, float(rng.random() < probability)


def train(count=50_000, epochs=8, seed=20260919):
    rng = random.Random(seed)
    rows = [example(rng) for _ in range(count)]
    weights = {name: 0.0 for name in FEATURES}
    bias = 0.0
    learning_rate = 0.035
    for _ in range(epochs):
        rng.shuffle(rows)
        for row, label in rows:
            prediction = sigmoid(bias + sum(weights[name] * row[name] for name in FEATURES))
            error = prediction - label
            bias -= learning_rate * error
            for name in FEATURES:
                weights[name] -= learning_rate * error * row[name]
        learning_rate *= 0.72
    return {"modelVersion": "synthetic-logreg-v1", "bias": bias, "weights": weights}


if __name__ == "__main__":
    output = Path(__file__).parent / "model" / "weights.json"
    result = train()
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {output}")
