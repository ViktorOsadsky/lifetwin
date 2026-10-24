"""Exact-label metrics with abstention; no external ML dependencies."""
import argparse
import json


def indexed(rows, gold=False):
    result = {}
    if not isinstance(rows, list): raise ValueError('Expected a JSON array')
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not row['id']:
            raise ValueError('Every row needs a nonempty string ID')
        if row['id'] in result: raise ValueError('Duplicate ID: ' + row['id'])
        if 'label' not in row: raise ValueError('Missing label: ' + row['id'])
        label = row.get('label')
        if (gold or label is not None) and (not isinstance(label, str) or not label):
            raise ValueError('Label must be a nonempty string or prediction null')
        result[row['id']] = row
    return result


def score(gold_rows, prediction_rows):
    gold, predictions = indexed(gold_rows, True), indexed(prediction_rows)
    if not gold: raise ValueError('No gold examples; accuracy undefined')
    unknown = set(predictions) - set(gold)
    if unknown: raise ValueError('Unknown prediction IDs: ' + ','.join(sorted(unknown)))
    accepted = [(key, row['label']) for key, row in predictions.items() if row.get('label') is not None]
    correct = sum(label == gold[key]['label'] for key, label in accepted)
    per_label = {}
    for label in sorted({r['label'] for r in gold.values()} | {label for _, label in accepted}):
        tp = sum(predicted == label and gold[key]['label'] == label for key, predicted in accepted)
        fp = sum(predicted == label and gold[key]['label'] != label for key, predicted in accepted)
        fn = sum(row['label'] == label and predictions.get(key, {}).get('label') != label for key, row in gold.items())
        per_label[label] = {'true_positive': tp, 'false_positive': fp, 'false_negative': fn,
                            'precision': tp / (tp + fp) if tp + fp else None,
                            'recall': tp / (tp + fn) if tp + fn else None}
    return {'total': len(gold), 'accepted': len(accepted), 'correct': correct,
            'incorrect': len(accepted) - correct, 'abstained': len(gold) - len(accepted),
            'missing_prediction_ids': sorted(set(gold) - set(predictions)),
            'coverage': len(accepted) / len(gold),
            'accepted_accuracy': correct / len(accepted) if accepted else None,
            'task_success': correct / len(gold), 'per_label': per_label}


def audit_groups(train_rows, test_rows):
    indexed(train_rows, True); indexed(test_rows, True)
    groups = []
    for rows in (train_rows, test_rows):
        group = set()
        for row in rows:
            if not isinstance(row.get('group'), str) or not row['group']:
                raise ValueError('Missing group for ' + row['id'])
            group.add(row['group'])
        groups.append(group)
    overlap = sorted(groups[0] & groups[1])
    if overlap: raise ValueError('Leaked groups: ' + ','.join(overlap))
    if {r['id'] for r in train_rows} & {r['id'] for r in test_rows}:
        raise ValueError('Leaked IDs')
    if not train_rows or not test_rows: raise ValueError('Both splits must be nonempty')
    return {'group_overlap': [], 'train_groups': len(groups[0]), 'test_groups': len(groups[1])}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gold'); parser.add_argument('predictions')
    args = parser.parse_args()
    print(json.dumps(score(json.load(open(args.gold)), json.load(open(args.predictions))), indent=2))
