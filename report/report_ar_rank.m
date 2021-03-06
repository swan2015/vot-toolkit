function [document, scores] = report_ar_rank(context, experiment, trackers, sequences, varargin)
% report_ar_rank Generate a report based on A-R ranking
%
% Performs A-R ranking analysis and generates a report based on the results.
%
% Input:
% - context (structure): Report context structure.
% - experiment (struct): An experiment structure.
% - trackers (cell): An array of tracker structures.
% - sequences (cell): An array of sequence structures.
% - varargin[UsePractical] (boolean): Use practical difference.
% - varargin[UseTags] (boolean): Rank according to tags (otherwise rank according to sequences).
% - varargin[Average] (string): How to compute average rank.
%     - weighted_mean: Average ranks, average values by taking into account length
%     - mean: Average ranks, average values
%     - pooled: gather all frames and compute ranking on a single combined sequence
% - varargin[Alpha] (double): Statistical significance parameter.
% - varargin[Adaptation] (string): Statistical significance parameter.
% - varargin[HideLegend] (boolean): Hide legend in plots.
%
% Output:
% - document (structure): Resulting document structure.
% - scores (struct): Averaged ranks for entire set.
%

usetags = get_global_variable('report_tags', true);
usepractical = get_global_variable('report_ar_practical', true);
orderingplot = get_global_variable('report_ar_ordering', true);
hidelegend = get_global_variable('report_legend_hide', false);
arplot = get_global_variable('report_ar_arplot', true);
average = get_global_variable('report_ar_average', 'weighted_mean');
adaptation = get_global_variable('report_ar_adaptation', 'mean');
sensitivity = get_global_variable('report_ar_sensitivity', 30);
alpha = get_global_variable('report_ar_alpha', 0.05);
table_format = get_global_variable('report_ar_table_format', 'accrob'); % joined, rankscores, accrob, fragmented
table_orientation = get_global_variable('report_ar_table_orientation', 'trackers'); % trackers, selectors, trackerscores, selectorscores

for i = 1:2:length(varargin)
    switch lower(varargin{i})
        case 'usepractical'
            usepractical = varargin{i+1};
        case 'usetags'
            usetags = varargin{i+1};
        case 'average'
            average = varargin{i+1};
        case 'alpha'
            alpha = varargin{i+1};
        case 'adaptation'
            adaptation = varargin{i+1};
        case 'hidelegend'
            hidelegend = varargin{i+1};
        otherwise
            error(['Unknown switch ', varargin{i}, '!']) ;
    end
end


if ~strcmp(experiment.type, 'supervised')
   error('A-R Ranking analysis only suitable for supervised experiments!');
end

if numel(trackers) < 2
    error('Ranking analysis requires two or more trackers.');
end;

if ~any(strcmp(average, {'mean', 'weighted_mean', 'pooled'}))
   error('Unknown averaging technique "%s"!', average);
end
document = document_create(context, 'ar_rank', 'title', 'AR ranking');

trackers_hash = md5hash(strjoin((cellfun(@(x) x.identifier, trackers, 'UniformOutput', false)), '-'), 'Char', 'hex');
parameters_hash = md5hash(sprintf('%f-%d-%d-%s', alpha, usetags, usepractical, adaptation));

tags = {};

if usetags && isfield(experiment, 'tags')
    tags = union(experiment.tags, {'all'});
    sequences_hash = md5hash(strjoin(tags, '-'), 'Char', 'hex');
else
    sequences_hash = md5hash(strjoin((cellfun(@(x) x.name, sequences, 'UniformOutput', false)), '-'), 'Char', 'hex');
end;

cache_identifier = sprintf('ranking_%s_%s_%s_%s', experiment.name, trackers_hash, sequences_hash, parameters_hash);

result = document_cache(context, cache_identifier, @analyze_accuracy_robustness, experiment, trackers, ...
    sequences, 'tags', tags, 'usepractical', usepractical, ...
    'alpha', alpha, 'adaptation', adaptation);

if usetags
    % When using tags we have inserted a separate one for this
    mask = strcmp('tag_all', result.tags);

    result.accuracy.pooled_values = result.accuracy.values(mask, :);
    result.robustness.pooled_values = result.robustness.values(mask, :);
    result.robustness.pooled_normalized = result.robustness.normalized(mask, :);
    result.accuracy.pooled_ranks = result.accuracy.ranks(mask, :);
    result.robustness.pooled_ranks = result.robustness.ranks(mask, :);

    % Now remove the 'all' tag from results
    result.accuracy.values = result.accuracy.values(~mask, :);
    result.accuracy.ranks = result.accuracy.ranks(~mask, :);
    result.robustness.values = result.robustness.values(~mask, :);
    result.robustness.normalized = result.robustness.normalized(~mask, :);
    result.robustness.ranks = result.robustness.ranks(~mask, :);
    result.lengths = result.lengths(~mask);
    result.tags = result.tags(~mask);

end

result.accuracy.weighted_mean_ranks = nanmean(result.accuracy.ranks, 1);
result.robustness.weighted_mean_ranks = nanmean(result.robustness.ranks, 1);

useable = result.lengths > 0;
result.accuracy.weighted_mean_values = sum(result.accuracy.values(useable, :) ...
    .* repmat(result.lengths(useable), 1, length(trackers)), 1) ./ sum(result.lengths(useable));
result.robustness.weighted_mean_values = sum(result.robustness.values(useable, :) ...
    .* repmat(result.lengths(useable), 1, length(trackers)), 1) ./ sum(result.lengths(useable));
result.robustness.weighted_mean_normalized = sum(result.robustness.normalized(useable, :) ...
    .* repmat(result.lengths(useable), 1, length(trackers)), 1) ./ sum(result.lengths(useable));

result.accuracy.mean_ranks = nanmean(result.accuracy.ranks, 1);
result.robustness.mean_ranks = nanmean(result.robustness.ranks, 1);

result.accuracy.mean_values = nanmean(result.accuracy.values, 1);
result.robustness.mean_values = nanmean(result.robustness.values, 1);
result.robustness.mean_normalized = nanmean(result.robustness.normalized, 1);

switch average

    case 'weighted_mean'

        values = cat(2, result.accuracy.weighted_mean_ranks', ...
            result.robustness.weighted_mean_ranks', ...
            result.accuracy.weighted_mean_values', ...
            result.robustness.weighted_mean_values');

    case 'mean'

        values = cat(2, result.accuracy.mean_ranks', ...
            result.robustness.mean_ranks', ...
            result.accuracy.mean_values', ...
            result.robustness.mean_values');

    case 'pool'

        if usetags
            values = cat(2, result.accuracy.pooled_ranks', ...
                result.robustness.pooled_ranks', ...
                result.accuracy.pooled_values', ...
                result.robustness.pooled_values');
        else
            values = cat(2, result.accuracy.weighted_mean_ranks', ...
                result.robustness.weighted_mean_ranks', ...
                result.accuracy.weighted_mean_values', ...
                result.robustness.weighted_mean_values');
        end
end

scores.name = 'A-R rank';
scores.values = values;
scores.ids = {'arank', 'rrank', 'overlap', 'failures'};
scores.names = {'A-Rank', 'R-Rank', 'Overlap', 'Failures'};
scores.order = {'ascending', 'ascending', 'descending', 'ascending'};

tracker_labels = cellfun(@(x) iff(isfield(x.metadata, 'verified') && x.metadata.verified, [x.label, '*'], x.label), trackers, 'UniformOutput', 0);

print_text('Writing ranking table ...');

document.section('Experiment %s', experiment.name);

if arplot

    ar_and_rank_plot(document, sprintf('%s_mean', experiment.name), ...
        sprintf('experiment %s (mean)', experiment.name), ...
        trackers, result.accuracy.mean_ranks, ...
        result.robustness.mean_ranks, ...
        result.accuracy.mean_values, ...
        result.robustness.mean_normalized, sensitivity, hidelegend);

    ar_and_rank_plot(document, sprintf('%s_weighted_mean', experiment.name), ...
        sprintf('experiment %s (weighted_mean)', experiment.name), ...
        trackers, result.accuracy.weighted_mean_ranks, ...
        result.robustness.weighted_mean_ranks, ...
        result.accuracy.weighted_mean_values, ...
        result.robustness.weighted_mean_normalized, sensitivity, hidelegend);

    if usetags

        ar_and_rank_plot(document, sprintf('%s_pooled', experiment.name), ...
        sprintf('experiment %s (pooled)', experiment.name), ...
        trackers, result.accuracy.pooled_ranks, ...
        result.robustness.pooled_ranks, ...
        result.accuracy.pooled_values, ...
        result.robustness.pooled_normalized, sensitivity, hidelegend);

    end

end;

selector_tags = result.tags;

score_tags = {'A-Rank', 'R-Rank', 'Overlap', 'Failures'};
score_sorting = {'ascending', 'ascending', 'descending', 'ascending'};
raw_scores = cat(3, result.accuracy.ranks', ...
    result.robustness.ranks', ...
    result.accuracy.values', ...
    result.robustness.values');
raw_scores = cat(2, raw_scores, cat(3, result.accuracy.mean_ranks', ...
    result.robustness.mean_ranks', ...
    result.accuracy.mean_values', ...
    result.robustness.mean_values'));
raw_scores = cat(2, raw_scores, cat(3, result.accuracy.weighted_mean_ranks', ...
    result.robustness.weighted_mean_ranks', ...
    result.accuracy.weighted_mean_values', ...
    result.robustness.weighted_mean_values'));

table_selector_tags = selector_tags;
table_selector_tags{end+1} = create_table_cell('Mean', 'class', 'average');
table_selector_tags{end+1} = create_table_cell('Weighted mean', 'class', 'average');

if usetags
    raw_scores = cat(2, raw_scores, cat(3, result.accuracy.pooled_ranks', ...
        result.robustness.pooled_ranks', ...
        result.accuracy.pooled_values', ...
        result.robustness.pooled_values'));
    table_selector_tags{end+1} = create_table_cell('Pooled', 'class', 'average');
end

switch table_format
    case 'joined'
        print_scores_table(document, raw_scores, score_sorting, score_tags, tracker_labels, table_selector_tags, table_orientation, 'Ranks and raw scores');
    case 'rankscores'
        print_scores_table(document, raw_scores(:, :, 1:2), score_sorting(1:2), score_tags(1:2), tracker_labels, table_selector_tags, table_orientation, 'Ranks');
        print_scores_table(document, raw_scores(:, :, 3:4), score_sorting(3:4), score_tags(3:4), tracker_labels, table_selector_tags, table_orientation, 'Raw scores');
    case 'accrob'
        print_scores_table(document, raw_scores(:, :, [1,3]), score_sorting([1,3]), score_tags([1,3]), tracker_labels, table_selector_tags, table_orientation, 'Accuracy');
        print_scores_table(document, raw_scores(:, :, [2,4]), score_sorting([2,4]), score_tags([2,4]), tracker_labels, table_selector_tags, table_orientation, 'Robustness');
    case 'fragmented'
        for t = 1:numel(score_tags)
            print_scores_table(document, raw_scores(:, :, t), score_sorting(t), score_tags(t), tracker_labels, table_selector_tags, table_orientation, score_tags{t});
        end;
end

document.subsection('Detailed plots');

if orderingplot

    h = plot_ordering(trackers, result.accuracy.ranks, selector_tags, ...
        'flip', 1, 'legend', ~hidelegend);
    document.figure(h, sprintf('ordering_accuracy_%s', experiment.name), ...
        'Ranking orderings for accuracy rank');

    close(h);

    h = plot_ordering(trackers, result.accuracy.values, selector_tags, ...
        'scope', [0, 1], 'type', 'Overall overlap', 'legend', ~hidelegend);
    document.figure(h, sprintf('ordering_overlap_%s', experiment.name), ...
        'Orderings for overall overlap');

    close(h);

    h = plot_ordering(trackers, result.robustness.ranks, selector_tags, ...
        'flip', 1, 'legend', ~hidelegend);
    document.figure(h, sprintf('ordering_robustness_%s', experiment.name), ...
        'Ranking orderings for robustness rank');

    close(h);

    robustness = result.robustness.normalized .* sensitivity;

    h = plot_ordering(trackers, robustness, selector_tags, ...
        'scope', [0, max(robustness(:))+eps], 'type', ...
        'Failures', 'legend', ~hidelegend);

    document.figure(h, sprintf('ordering_failures_%s', experiment.name), ...
        'Orderings for failures');

    close(h);

end;

if arplot

    for l = 1:length(selector_tags)

        plot_title = sprintf('Ranking plot for tag %s in experiment %s', ...
            selector_tags{l}, experiment.name);
        plot_id = sprintf('rankingplot_%s_%s', ...
            experiment.name, selector_tags{l});

        hf = plot_ranking(trackers, result.accuracy.ranks(l, :)', ...
            result.robustness.ranks(l, :)', ...
            'title', plot_title, 'limit', numel(trackers), 'legend', ~hidelegend);

        document.figure(hf, plot_id, plot_title);

        close(hf);

        plot_title = sprintf('AR plot for tag %s in experiment %s', ...
            selector_tags{l}, experiment.name);
        plot_id = sprintf('arplot_%s_%s', experiment.name, selector_tags{l});

        hf = plot_ar(trackers, result.accuracy.values(l, :), ...
            result.robustness.normalized(l, :), ...
            'title', plot_title, 'sensitivity', sensitivity, 'legend', ~hidelegend);

        document.figure(hf, plot_id, plot_title);

        close(hf);

    end;

end;

document.write();

end

% --------------------------------------------------------------------- %

function print_scores_table(document, scores, score_sorting, score_tags, tracker_labels, selector_tags, orientation, title)

    % Scores - selectors x trackers x scores

    score_count = numel(score_tags);
    selector_count = numel(selector_tags);
    tracker_count = numel(tracker_labels);

    switch orientation
        case 'trackers'
            row_tags = tracker_labels;
            column_labels = selector_tags;
            row_scores = false;
            sort_columns = false;
        case 'selectors'
            row_tags = selector_tags;
            column_labels = tracker_labels;
            row_scores = false;
            sort_columns = true;
        case 'trackerscores'
            row_tags = tracker_labels;
            column_labels = selector_tags;
            row_scores = true;
            sort_columns = true;
        case 'selectorscores'
            row_tags = selector_tags;
            column_labels = tracker_labels;
            row_scores = true;
            sort_columns = false;
        otherwise
            error('Unknown format %s', orientation);
    end

    column_labels = column_labels(:)';
    row_tags = row_tags(:);

    row_count = numel(row_tags);
    column_count = numel(column_labels);

    if sort_columns
        table_data = cell(tracker_count * score_count, selector_count);

        for s = 1:score_count
            score_table_data = highlight_best_rows(num2cell(scores(:, :, s)), ...
                repmat(score_sorting(s), 1, numel(selector_tags)));
            table_data(s:score_count:end, :) = score_table_data;
        end

        if ~row_scores
            table_data = table_data';
        end
    else
        table_data = cell(tracker_count, selector_count * score_count);

        for s = 1:score_count
            score_table_data = highlight_best_rows(num2cell(scores(:, :, s)), ...
                repmat(score_sorting(s), 1, numel(selector_tags)));
            table_data(:, s:score_count:end) = score_table_data;
        end

        if row_scores
            table_data = table_data';
        end
    end

    if row_scores

        if score_count > 1
            row_tags_exp = cell(score_count * row_count, 2);
            row_tags_exp(:, 1) = repmat({struct()}, 1, row_count * score_count);
            row_tags_exp(1:score_count:end, 1) = cellfun(@(x) create_table_cell(x, 'rows', score_count), row_tags, 'UniformOutput', false);
            row_tags_exp(:, 2) = score_tags(repmat(1:score_count, 1, row_count));
            row_tags = row_tags_exp;
        end

    else

        if score_count > 1
            column_labels_exp = cell(2, score_count * column_count);
            column_labels_exp(1, :) = repmat({struct()}, 1, column_count * score_count);
            column_labels_exp(1, 1:score_count:end) = cellfun(@(x) create_table_cell(x, 'columns', score_count), column_labels, 'UniformOutput', false);
            column_labels_exp(2, :) = score_tags(repmat(1:score_count, 1, column_count));
            column_labels = column_labels_exp;
        end

    end;

    document.table(table_data, 'columnLabels', column_labels, 'rowLabels', row_tags, 'title', title);

end

function ar_and_rank_plot(document, identifier, title, trackers, ...
    accuracy_ranks, robustness_ranks, accuracy_values, ...
    robustness_values, sensitivity, hidelegend)

    plot_title = sprintf('Ranking plot for %s', title);
    plot_id = sprintf('rankingplot_%s', identifier);

    hf = plot_ranking(trackers, accuracy_ranks, ...
        robustness_ranks, ...
        'title', plot_title, 'limit', numel(trackers), 'legend', ~hidelegend);

    document.figure(hf, plot_id, plot_title);

    close(hf);

    plot_title = sprintf('AR plot for %s', title);
    plot_id = sprintf('arplot_%s', identifier);

    hf = plot_ar(trackers, accuracy_values, ...
        robustness_values, ...
        'title', plot_title, 'sensitivity', sensitivity, 'legend', ~hidelegend);

    document.figure(hf, plot_id, plot_title);

    close(hf);

end
