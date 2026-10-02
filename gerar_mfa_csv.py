# Author: Gabriel Jabour
# Version: 1.0

import re
from pathlib import Path
from typing import Optional


def normalize_state(raw: str) -> Optional[str]:
    value = (raw or "").strip().lower()
    mapping = {
        "disable": "Disable",
        "disabled": "Disable",
        "enable": "Enable",
        "enabled": "Enable",
        "enforced": "Enforced",
        "enforce": "Enforced",
    }
    return mapping.get(value)


def main() -> None:
    # Pergunta ao usuário o estado desejado de MFA
    valid_states = ["Disable", "Enforced", "Enable"]
    state_raw = input("Digite o estado de MFA desejado (Disable, Enforced ou Enable): ")
    state = normalize_state(state_raw)

    while state not in valid_states:
        print("⚠️ Estado inválido. Digite um dos seguintes: Disable, Enforced ou Enable.")
        state_raw = input("Digite o estado de MFA desejado (Disable, Enforced ou Enable): ")
        state = normalize_state(state_raw)

    input_path = Path("users_mfa.txt")
    if not input_path.exists():
        raise SystemExit(f"Arquivo não encontrado: {input_path.resolve()}")

    # 1) Leia o input salvo
    lines = input_path.read_text(encoding="utf-8").splitlines()
    lines = [l.strip() for l in lines if l.strip()]

    # 2) Remova o cabeçalho
    if lines and re.match(r"userPrincipalName", lines[0], re.IGNORECASE):
        lines = lines[1:]

    # 3) Parse e monte os registros
    records: list[dict[str, str]] = []
    for line in lines:
        parts = re.split(r"\s+", line)
        upn = parts[0] if parts else ""
        if "@" not in upn:
            continue
        records.append({"userPrincipalName": upn, "State": state})

    # 4) Gere CSV
    output_path = Path("mfa_enforced.csv")
    try:
        import pandas as pd  # type: ignore

        df = pd.DataFrame(records)
        df.to_csv(output_path, index=False, encoding="utf-8")
        count = len(df.index)
    except Exception:
        import csv

        with output_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["userPrincipalName", "State"])
            writer.writeheader()
            writer.writerows(records)
        count = len(records)

    print(f"✅ Gerado: {output_path} ({count} registros)")


if __name__ == "__main__":
    main()
