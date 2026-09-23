"""Arrange captured facts by distance from the paste location; never invent a caret."""
from context_evidence import resolve


def clip(text, size, tail=False):
    data = text.encode('utf-8')
    return (data[-size:] if tail else data[:size]).decode('utf-8', errors='ignore')


def hierarchical_destination(context):
    evidence = resolve(context)
    destination = {
        'context_version': 3,
        'priority_order': ['insertion', 'field', 'document', 'application'],
        'insertion': {'available': False},
        'field': {}, 'document': {}, 'application': {},
    }
    if not evidence:
        destination['document'] = {'unanchored_context': clip(context, 1400)}
        return destination
    raw = evidence['raw']
    insertion = raw.get('insertion')
    if insertion is not None:
        caps = {'before': 600, 'after': 240, 'replacing': 160}
        if (not isinstance(insertion, dict)
                or insertion.get('source') not in ('ax_value_and_selected_text_range', 'ax_text_marker_range')
                or type(insertion.get('isReplacement')) is not bool
                or any(not isinstance(insertion.get(k), str) or len(insertion[k].encode()) > cap
                       for k, cap in caps.items())):
            raise ValueError('Invalid insertion context. Nothing was sent.')
        # Preserve the exact text adjacent to the caret. Newlines separate the
        # current line from earlier/later prose; byte caps do not infer semantics.
        before, after = insertion['before'], insertion['after']
        local_before = clip(before.rsplit('\n', 1)[-1], 300, tail=True)
        local_after = clip(after.split('\n', 1)[0], 160)
        destination['insertion'] = {
            'available': True, 'source': insertion['source'],
            'before': local_before, 'after': local_after,
            'replacing': insertion['replacing'], 'isReplacement': insertion['isReplacement'],
        }
        earlier = before[:len(before)-len(local_before)]
        later = after[len(local_after):]
        if earlier:
            destination['document']['earlier_text'] = clip(earlier, 300, tail=True)
        if later:
            destination['document']['later_text'] = clip(later, 160)
    destination['field'] = {
        'label': evidence['label'], 'label_source': evidence['source'],
        'instructions': evidence['help'], 'ambiguous': evidence['ambiguous'],
        'destination_kind': raw.get('destinationKind', 'editable'),
    }
    if evidence['navigation']:
        destination['field']['location'] = 'browser toolbar'
        destination['field']['purpose'] = 'Enter a website address or search the web.'
    if evidence['scope']:
        destination['document']['section'] = clip(evidence['scope'], 240)
    # With a real insertion anchor, broad OCR adds competing draft text without
    # adding cursor evidence. Keep it only as explicitly unanchored background.
    if not destination['insertion']['available']:
        destination['document']['unanchored_context'] = clip(evidence['state'], 1000)
    destination['application'] = {
        'name': clip(str(raw.get('app', '')), 100),
    }
    if not destination['insertion']['available']:
        destination['application']['window_title'] = clip(str(raw.get('windowTitle', '')), 160)
    return destination
