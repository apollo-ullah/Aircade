# Aircade tennis opponent on Baseten

This Truss serves a CPU logistic-regression baseline that scores legal tennis
returns. The station API converts those scores into a varied plan; Swift keeps
physics and animation local.

```sh
cd baseten/tennis-opponent
python3 train_sim.py
python3 -m pip install --upgrade truss
truss login
truss push
```

Set the resulting production predict URL and API key before starting the station:

```sh
export BASETEN_TENNIS_URL="https://model-MODEL_ID.api.baseten.co/environments/production/predict"
export BASETEN_API_KEY="..."
./scripts/start-station.sh
```

Without both variables, `/api/tennis/opponent-plan` returns the same schema from
a deterministic local fallback. The key stays in the Node process and is never
included in the macOS app.
