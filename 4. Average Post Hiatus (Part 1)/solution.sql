SELECT
  user_id,
  post_date,
  LAG(post_date) OVER (PARTITION BY user_id ORDER BY post_date) as prev_post_date
FROM posts
WHERE post_date >= '2021-01-01' and post_date < '2022-01-01';
